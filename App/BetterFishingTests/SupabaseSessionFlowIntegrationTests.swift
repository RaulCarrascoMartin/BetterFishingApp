import XCTest
@_spi(Experimental) import Supabase
@testable import BetterFishing

@MainActor
final class SupabaseSessionFlowIntegrationTests: XCTestCase {
    private let tokenURL = "https://project-ref.supabase.co/auth/v1/token?grant_type=password"
    private let userURL = "https://project-ref.supabase.co/auth/v1/user"
    private let logoutURL = "https://project-ref.supabase.co/auth/v1/logout?scope=global"
    private let storageKey = "test-auth-token"
    private let fixedUserID = UUID(uuid: (0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11))

    override func setUp() {
        super.setUp()
        HTTPStubRegistry.shared.reset()
    }

    func testFullSessionFlowThroughRealCompositionRoot() async throws {
        HTTPStubRegistry.shared.register(.json(Self.sessionJSON), for: tokenURL)
        HTTPStubRegistry.shared.register(.json(Self.userJSON), for: userURL)
        HTTPStubRegistry.shared.register(HTTPStub(statusCode: 204), for: logoutURL)

        let auth = try makeAuthServiceViaCompositionRoot()
        let events = auth.stateChanges()

        let session = try await auth.signIn(email: "angler@example.com", password: "correct-horse")

        XCTAssertEqual(session.accessToken, "access-token-111")
        XCTAssertEqual(session.refreshToken, "refresh-token-222")
        XCTAssertEqual(session.user.id, fixedUserID)
        XCTAssertEqual(session.user.email, "angler@example.com")
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: tokenURL), 1)

        let current = try await auth.currentSession()
        let user = await auth.currentUser()
        XCTAssertEqual(current, session)
        XCTAssertEqual(user, session.user)

        try await auth.signOut()
        let sessionAfterSignOut = try await auth.currentSession()
        let userAfterSignOut = await auth.currentUser()
        XCTAssertNil(sessionAfterSignOut)
        XCTAssertNil(userAfterSignOut)
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: logoutURL), 1)

        let collected = try await collectEvents(from: events) { event in
            if case .signedOut = event { return true }
            return false
        }

        XCTAssertTrue(collected.contains { if case .signedIn = $0 { return true } else { return false } })
        XCTAssertTrue(collected.contains { if case .signedOut = $0 { return true } else { return false } })
    }

    func testSignInFailureThroughRealCompositionRootThrowsTypedErrorAndDoesNotEmitSignedIn() async throws {
        let errorBody: [String: Any] = ["message": "Invalid login credentials"]
        HTTPStubRegistry.shared.register(.json(errorBody, statusCode: 401), for: tokenURL)

        let auth = try makeAuthServiceViaCompositionRoot()
        let events = auth.stateChanges()

        do {
            _ = try await auth.signIn(email: "angler@example.com", password: "wrong-password")
            XCTFail("Expected signIn to throw")
        } catch let error as SupabaseBaseError {
            XCTAssertEqual(error, .signInFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        let collected = await collectEvents(from: events, for: .milliseconds(500))
        XCTAssertFalse(collected.contains { if case .signedIn = $0 { return true } else { return false } })
    }

    private func makeAuthServiceViaCompositionRoot() throws -> any SupabaseAuthProviding {
        let url = try XCTUnwrap(URL(string: "https://project-ref.supabase.co"))
        let configuration = SupabaseClientConfiguration(projectURL: url, anonKey: "test-anon-key")
        let options = SupabaseClientOptions(
            auth: .init(
                storage: InMemoryAuthLocalStorage(),
                storageKey: storageKey,
                autoRefreshToken: false
            ),
            global: .init(session: .mockSession())
        )
        let services = AppComposition.makeRootServices(
            arguments: [],
            supabaseConfiguration: configuration,
            supabaseOptions: options
        )
        let stack = try XCTUnwrap(services.supabase, "Config válida inyectada debe producir un stack")
        return stack.auth
    }

    private func collectEvents(
        from stream: AsyncStream<SupabaseAuthEvent>,
        untilTerminal: @escaping @Sendable (SupabaseAuthEvent) -> Bool,
        timeout: Duration = .seconds(5)
    ) async throws -> [SupabaseAuthEvent] {
        let collector = Task<[SupabaseAuthEvent], Never> {
            var collected: [SupabaseAuthEvent] = []
            for await event in stream {
                collected.append(event)
                if untilTerminal(event) {
                    break
                }
            }
            return collected
        }
        defer { collector.cancel() }

        return try await withThrowingTaskGroup(of: [SupabaseAuthEvent].self) { group in
            group.addTask { await collector.value }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CollectorTimeout()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CollectorTimeout()
            }
            return result
        }
    }

    private func collectEvents(
        from stream: AsyncStream<SupabaseAuthEvent>,
        for duration: Duration
    ) async -> [SupabaseAuthEvent] {
        let task = Task<[SupabaseAuthEvent], Never> {
            var collected: [SupabaseAuthEvent] = []
            for await event in stream {
                collected.append(event)
            }
            return collected
        }
        try? await Task.sleep(for: duration)
        task.cancel()
        return await task.value
    }

    private struct CollectorTimeout: Error {}

    private static var sessionJSON: [String: Any] {
        [
            "access_token": "access-token-111",
            "token_type": "bearer",
            "expires_in": 3600,
            "expires_at": 1_893_456_000,
            "refresh_token": "refresh-token-222",
            "user": userJSON,
        ]
    }

    private static var userJSON: [String: Any] {
        [
            "id": "11111111-1111-1111-1111-111111111111",
            "aud": "authenticated",
            "role": "authenticated",
            "email": "angler@example.com",
            "created_at": "2026-09-20T10:00:00Z",
            "updated_at": "2026-09-20T10:00:00Z",
            "app_metadata": [String: Any](),
            "user_metadata": [String: Any](),
            "is_anonymous": false,
        ]
    }
}