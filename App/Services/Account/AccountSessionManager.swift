import Foundation
import os

actor AccountSessionManager: AccountSessionManaging {
    private static let logger = Logger(subsystem: "com.betterfishing.BetterFishing", category: "Account")

    private let auth: any SupabaseAuthProviding
    nonisolated let sessionState: AsyncStream<AccountSessionState>
    private nonisolated let sessionContinuation: AsyncStream<AccountSessionState>.Continuation

    init(auth: any SupabaseAuthProviding) {
        self.auth = auth
        let (stream, continuation) = AsyncStream<AccountSessionState>.makeStream(bufferingPolicy: .unbounded)
        self.sessionState = stream
        self.sessionContinuation = continuation

        let projectionTask = Task { [auth, continuation] in
            let currentUser = await auth.currentUser()
            if let currentUser {
                continuation.yield(.signedIn(currentUser))
            }
            for await event in auth.stateChanges() {
                switch event {
                case .signedIn(let session), .sessionRestored(let session):
                    continuation.yield(.signedIn(session.user))
                case .signedOut:
                    continuation.yield(.signedOut)
                }
            }
        }
        continuation.onTermination = { _ in
            projectionTask.cancel()
        }
    }

    var currentUser: SupabaseUser? {
        get async {
            await auth.currentUser()
        }
    }

    func signUp(email: String, password: String) async throws -> AccountSignUpOutcome {
        do {
            let result = try await auth.signUp(email: email, password: password)
            switch result {
            case .signedIn(let session):
                try await ensureSessionPersisted()
                sessionContinuation.yield(.signedIn(session.user))
                Self.logger.info("Cuenta creada: \(session.user.id, privacy: .public)")
                return .signedIn
            case .emailConfirmationRequired:
                Self.logger.info("Cuenta creada, pendiente de confirmación de email")
                return .emailConfirmationRequired
            }
        } catch let error as SupabaseBaseError {
            switch error {
            case .sessionUnavailable:
                throw AccountError.sessionUnavailable
            default:
                throw AccountError.signUpFailed(Self.errorText(error))
            }
        } catch {
            throw AccountError.signUpFailed(Self.errorText(error))
        }
    }

    /// Evita mostrar estado "conectado" cuando los servicios no podrán leer la sesión.
    private func ensureSessionPersisted() async throws {
        guard try await auth.currentSession() != nil else {
            Self.logger.error("Login correcto pero la sesión no quedó almacenada")
            throw SupabaseBaseError.sessionUnavailable
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            let session = try await auth.signIn(email: email, password: password)
            try await ensureSessionPersisted()
            sessionContinuation.yield(.signedIn(session.user))
            Self.logger.info("Sesión iniciada: \(session.user.id, privacy: .public)")
        } catch let error as SupabaseBaseError {
            switch error {
            case .sessionUnavailable:
                throw AccountError.sessionUnavailable
            default:
                throw AccountError.signInFailed(Self.errorText(error))
            }
        } catch {
            throw AccountError.signInFailed(Self.errorText(error))
        }
    }

    func signOut() async throws {
        do {
            try await auth.signOut()
            sessionContinuation.yield(.signedOut)
            Self.logger.info("Sesión cerrada")
        } catch let error as SupabaseBaseError {
            switch error {
            case .sessionUnavailable:
                throw AccountError.sessionUnavailable
            default:
                throw AccountError.signOutFailed(Self.errorText(error))
            }
        } catch {
            throw AccountError.signOutFailed(Self.errorText(error))
        }
    }

    private static func errorText(_ error: Error) -> String {
        if let baseError = error as? SupabaseBaseError, let reason = baseError.reasonDescription {
            return reason
        }
        return error.localizedDescription
    }
}