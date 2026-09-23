import Foundation
@_spi(Experimental) import Supabase

actor SupabaseAuthService: SupabaseAuthProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func signUp(email: String, password: String) async throws -> SupabaseSession {
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            guard let session = response.session else {
                throw SupabaseBaseError.signUpFailed
            }
            return Self.makeSession(from: session)
        } catch let error as SupabaseBaseError {
            throw error
        } catch {
            throw SupabaseBaseError.signUpFailed
        }
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            return Self.makeSession(from: session)
        } catch let error as SupabaseBaseError {
            throw error
        } catch {
            throw SupabaseBaseError.signInFailed
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch let error as SupabaseBaseError {
            throw error
        } catch {
            throw SupabaseBaseError.signOutFailed
        }
    }

    func currentUser() async -> SupabaseUser? {
        guard let user = client.auth.currentUser else {
            return nil
        }
        return Self.makeUser(from: user)
    }

    func currentSession() async throws -> SupabaseSession? {
        guard let session = client.auth.currentSession else {
            return nil
        }
        return Self.makeSession(from: session)
    }

    nonisolated func stateChanges() -> AsyncStream<SupabaseAuthEvent> {
        let (stream, continuation) = AsyncStream<SupabaseAuthEvent>.makeStream()

        let task = Task { [client] in
            for await (event, session) in client.auth.authStateChanges {
                switch event {
                case .initialSession:
                    if let session {
                        continuation.yield(.sessionRestored(Self.makeSession(from: session)))
                    }
                case .signedIn:
                    if let session {
                        continuation.yield(.signedIn(Self.makeSession(from: session)))
                    }
                case .signedOut:
                    continuation.yield(.signedOut)
                default:
                    break
                }
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }

        return stream
    }

    private nonisolated static func makeSession(from session: Supabase.Session) -> SupabaseSession {
        SupabaseSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt),
            user: makeUser(from: session.user)
        )
    }

    private nonisolated static func makeUser(from user: Supabase.User) -> SupabaseUser {
        SupabaseUser(id: user.id, email: user.email, createdAt: user.createdAt)
    }
}