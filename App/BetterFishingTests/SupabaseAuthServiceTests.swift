import XCTest
@_spi(Experimental) import Supabase
@testable import BetterFishing

final class SupabaseAuthServiceTests: XCTestCase {
    private let signUpURL = "https://project-ref.supabase.co/auth/v1/signup"
    private let tokenURL = "https://project-ref.supabase.co/auth/v1/token?grant_type=password"
    private let logoutURL = "https://project-ref.supabase.co/auth/v1/logout?scope=global"
    private let storageKey = "test-auth-token"
    private let fixedUserID = UUID(uuid: (0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11))

    override func setUp() {
        super.setUp()
        HTTPStubRegistry.shared.reset()
    }

    func testSignUpReturnsSupabaseSession() async throws {
        HTTPStubRegistry.shared.register(.json(Self.sessionJSON), for: signUpURL)

        let auth = try makeAuthService()

        let session = try await auth.signUp(email: "angler@example.com", password: "correct-horse")

        XCTAssertEqual(session.accessToken, "access-token-111")
        XCTAssertEqual(session.refreshToken, "refresh-token-222")
        XCTAssertEqual(session.user.id, fixedUserID)
        XCTAssertEqual(session.user.email, "angler@example.com")
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: signUpURL), 1)
    }

    func testSignInReturnsSupabaseSession() async throws {
        HTTPStubRegistry.shared.register(.json(Self.sessionJSON), for: tokenURL)

        let auth = try makeAuthService()

        let session = try await auth.signIn(email: "angler@example.com", password: "correct-horse")

        XCTAssertEqual(session.accessToken, "access-token-111")
        XCTAssertEqual(session.refreshToken, "refresh-token-222")
        XCTAssertEqual(session.user.email, "angler@example.com")
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: tokenURL), 1)
    }

    func testSignInWithInvalidCredentialsThrowsSignInFailed() async throws {
        let errorBody: [String: Any] = ["message": "Invalid login credentials"]
        HTTPStubRegistry.shared.register(.json(errorBody, statusCode: 401), for: tokenURL)

        let auth = try makeAuthService()

        do {
            _ = try await auth.signIn(email: "angler@example.com", password: "wrong-password")
            XCTFail("Expected signIn to throw")
        } catch let error as SupabaseBaseError {
            XCTAssertEqual(error, .signInFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSignOutTerminatesSession() async throws {
        HTTPStubRegistry.shared.register(.json(Self.sessionJSON), for: tokenURL)
        HTTPStubRegistry.shared.register(HTTPStub(statusCode: 204), for: logoutURL)

        let auth = try makeAuthService()
        _ = try await auth.signIn(email: "angler@example.com", password: "correct-horse")

        try await auth.signOut()

        let session = try await auth.currentSession()
        let user = await auth.currentUser()
        XCTAssertNil(session)
        XCTAssertNil(user)
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: logoutURL), 1)
    }

    func testCurrentSessionAndCurrentUserReflectStateAfterSignIn() async throws {
        HTTPStubRegistry.shared.register(.json(Self.sessionJSON), for: tokenURL)

        let auth = try makeAuthService()
        let expected = try await auth.signIn(email: "angler@example.com", password: "correct-horse")

        let session = try await auth.currentSession()
        let user = await auth.currentUser()

        XCTAssertEqual(session, expected)
        XCTAssertEqual(user, expected.user)
        XCTAssertEqual(session?.user.email, "angler@example.com")
    }

    func testStateChangesEmitsSignedInAndSignedOut() async throws {
        HTTPStubRegistry.shared.register(.json(Self.sessionJSON), for: tokenURL)
        HTTPStubRegistry.shared.register(HTTPStub(statusCode: 204), for: logoutURL)

        let auth = try makeAuthService()
        let events = auth.stateChanges()

        _ = try await auth.signIn(email: "angler@example.com", password: "correct-horse")
        try await auth.signOut()

        let collected = try await collectEvents(from: events) { event in
            if case .signedOut = event { return true }
            return false
        }

        XCTAssertTrue(collected.contains { if case .signedIn = $0 { return true } else { return false } })
        XCTAssertTrue(collected.contains { if case .signedOut = $0 { return true } else { return false } })
    }

    func testStateChangesEmitsSessionRestoredFromSeededStorage() async throws {
        let storage = InMemoryAuthLocalStorage()
        let createdAt = Date(timeIntervalSince1970: 1_789_999_200)
        let seed = SeededSessionBuilder.seededSession(userID: fixedUserID)
        try storage.store(key: storageKey, value: JSONEncoder().encode(seed))

        let auth = try makeAuthService(storage: storage)
        let events = auth.stateChanges()

        let collected = try await collectEvents(from: events) { event in
            if case .sessionRestored = event { return true }
            return false
        }

        guard case .sessionRestored(let restored) = collected.first else {
            XCTFail("Expected a sessionRestored event, got \(collected)")
            return
        }
        XCTAssertEqual(restored.accessToken, "seeded-access-token")
        XCTAssertEqual(restored.refreshToken, "seeded-refresh-token")
        XCTAssertEqual(restored.user.id, fixedUserID)
        XCTAssertEqual(restored.user.email, "seeded@example.com")
        XCTAssertEqual(restored.user.createdAt, createdAt)
    }

    private func makeAuthService(
        storage: AuthLocalStorage = InMemoryAuthLocalStorage()
    ) throws -> SupabaseAuthService {
        let supabaseURL = try XCTUnwrap(URL(string: "https://project-ref.supabase.co"))
        let options = SupabaseClientOptions(
            auth: .init(
                storage: storage,
                storageKey: storageKey,
                autoRefreshToken: false
            ),
            global: .init(session: .mockSession())
        )
        let client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: "test-anon-key",
            options: options
        )
        return SupabaseAuthService(client: client)
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

private enum SeededSessionBuilder {
    static func seededSession(userID: UUID) -> Supabase.Session {
        let createdAt = Date(timeIntervalSince1970: 1_789_999_200)
        let user = Supabase.User(
            id: userID,
            appMetadata: [:],
            userMetadata: [:],
            aud: "authenticated",
            email: "seeded@example.com",
            createdAt: createdAt,
            updatedAt: createdAt,
            isAnonymous: false
        )
        return Supabase.Session(
            accessToken: "seeded-access-token",
            tokenType: "bearer",
            expiresIn: 3600,
            expiresAt: 1_893_456_000,
            refreshToken: "seeded-refresh-token",
            user: user
        )
    }
}

final class InMemoryAuthLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}