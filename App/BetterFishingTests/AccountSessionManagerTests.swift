import XCTest

@testable import BetterFishing

final class AccountSessionManagerTests: XCTestCase {

    func testSignUpEmitsSignedIn() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        let manager = AccountSessionManager(auth: fake)

        try await manager.signUp(email: "angler@example.com", password: "correct-horse")

        let collected = await Self.collect(from: manager.sessionState, until: { state in
            if case .signedIn = state { return true }
            return false
        })

        XCTAssertTrue(collected.contains(.signedIn(SupabaseBaseFake.defaultUser)))
        XCTAssertEqual(fake.recordedSignUps.first?.email, "angler@example.com")
    }

    func testSignUpWithoutSessionReturnsEmailConfirmationRequiredAndDoesNotEmitSignedIn() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        fake.authSignUpResult = .emailConfirmationRequired
        let manager = AccountSessionManager(auth: fake)
        let stream = manager.sessionState

        let outcome = try await manager.signUp(email: "angler@example.com", password: "correct-horse")

        XCTAssertEqual(outcome, .emailConfirmationRequired)

        let collected = await Self.collect(from: stream, until: { _ in false }, timeout: .milliseconds(400))
        XCTAssertFalse(collected.contains { state in
            if case .signedIn = state { return true }
            return false
        })
    }

    func testSignInEmitsSignedIn() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        let manager = AccountSessionManager(auth: fake)

        try await manager.signIn(email: "angler@example.com", password: "correct-horse")

        let collected = await Self.collect(from: manager.sessionState, until: { state in
            if case .signedIn = state { return true }
            return false
        })

        XCTAssertTrue(collected.contains(.signedIn(SupabaseBaseFake.defaultUser)))
        XCTAssertEqual(fake.recordedSignIns.first?.email, "angler@example.com")
    }

    func testSignOutEmitsSignedOutAndClearsCurrentUser() async throws {
        let fake = SupabaseBaseFake()
        let manager = AccountSessionManager(auth: fake)

        try await manager.signOut()
        fake.isSessionActive = false

        let collected = await Self.collect(from: manager.sessionState, until: { $0 == .signedOut })
        XCTAssertTrue(collected.contains(.signedOut))

        let user = await manager.currentUser
        XCTAssertNil(user)
        XCTAssertEqual(fake.recordedSignOutCount, 1)
    }

    func testSignInFailureThrowsSignInFailedAndDoesNotEmitSignedIn() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        fake.authError = SupabaseBaseError.signInFailed(
            SupabaseAuthFailure(reason: .invalidCredentials, description: "Invalid login credentials")
        )
        let manager = AccountSessionManager(auth: fake)
        let stream = manager.sessionState

        do {
            try await manager.signIn(email: "angler@example.com", password: "wrong-password")
            XCTFail("Se esperaba AccountError.signInFailed")
        } catch let error as AccountError {
            guard case .signInFailed = error else {
                XCTFail("Se esperaba .signInFailed, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }

        let collected = await Self.collect(from: stream, until: { _ in false }, timeout: .milliseconds(400))

        XCTAssertFalse(collected.contains { state in
            if case .signedIn = state { return true }
            return false
        })
    }

    func testSignInFailureMessageStatesTheReasonWithoutDuplicatedPrefix() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        fake.authError = SupabaseBaseError.signInFailed(
            SupabaseAuthFailure(reason: .invalidCredentials, description: "Invalid login credentials")
        )
        let manager = AccountSessionManager(auth: fake)

        do {
            try await manager.signIn(email: "angler@example.com", password: "wrong-password")
            XCTFail("Se esperaba AccountError.signInFailed")
        } catch let error as AccountError {
            XCTAssertEqual(
                error.localizedDescription,
                "No se pudo iniciar sesión: las credenciales no son válidas."
            )
        }
    }

    func testSessionRestorationYieldsSignedInFirst() async throws {
        let fake = SupabaseBaseFake(stateChangesEvents: [.sessionRestored(SupabaseBaseFake.defaultSession)])
        fake.authSession = SupabaseBaseFake.defaultSession
        fake.isSessionActive = false
        let manager = AccountSessionManager(auth: fake)

        let collected = await Self.collect(from: manager.sessionState, until: { state in
            if case .signedIn = state { return true }
            return false
        })

        XCTAssertEqual(collected.first, .signedIn(SupabaseBaseFake.defaultUser))
    }

    private static func collect(
        from stream: AsyncStream<AccountSessionState>,
        until terminal: @escaping @Sendable (AccountSessionState) -> Bool,
        timeout: Duration = .seconds(2)
    ) async -> [AccountSessionState] {
        let collector = Task<[AccountSessionState], Never> {
            var collected: [AccountSessionState] = []
            for await state in stream {
                collected.append(state)
                if terminal(state) {
                    break
                }
            }
            return collected
        }
        let watchdog = Task<Void, Never> {
            try? await Task.sleep(for: timeout)
            collector.cancel()
        }
        defer {
            collector.cancel()
            watchdog.cancel()
        }
        return await collector.value
    }
}