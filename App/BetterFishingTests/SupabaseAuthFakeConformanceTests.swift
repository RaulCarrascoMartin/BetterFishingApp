import Foundation
import XCTest

@testable import BetterFishing

struct AuthTestDouble: SupabaseAuthProviding, Sendable {
    func signUp(email: String, password: String) async throws -> SupabaseSession {
        AuthTestDouble.session
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        AuthTestDouble.session
    }

    func signOut() async throws {}

    func currentUser() async -> SupabaseUser? {
        AuthTestDouble.session.user
    }

    func currentSession() async throws -> SupabaseSession? {
        AuthTestDouble.session
    }

    func stateChanges() -> AsyncStream<SupabaseAuthEvent> {
        AsyncStream<SupabaseAuthEvent> { continuation in
            continuation.yield(.sessionRestored(AuthTestDouble.session))
            continuation.yield(.signedOut)
            continuation.finish()
        }
    }

    static let user = SupabaseUser(
        id: UUID(uuid: (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)),
        email: "angler@example.com",
        createdAt: Date(timeIntervalSinceReferenceDate: 7_500_000)
    )

    static let session = SupabaseSession(
        accessToken: "access-token-123",
        refreshToken: "refresh-token-456",
        expiresAt: Date(timeIntervalSinceReferenceDate: 7_500_000 + 3_600),
        user: user
    )
}

final class SupabaseAuthFakeConformanceTests: XCTestCase {
    func testAuthTestDoubleIsUsableAsAnySupabaseAuthProviding() async throws {
        let auth: any SupabaseAuthProviding = AuthTestDouble()

        let user = await auth.currentUser()

        XCTAssertEqual(user?.email, "angler@example.com")
        let session = try await auth.currentSession()
        XCTAssertEqual(session?.accessToken, AuthTestDouble.session.accessToken)
    }

    func testAuthEventCasesAreDistinguishable() {
        let signedIn = SupabaseAuthEvent.signedIn(AuthTestDouble.session)
        let sessionRestored = SupabaseAuthEvent.sessionRestored(AuthTestDouble.session)
        let signedOut = SupabaseAuthEvent.signedOut

        XCTAssertEqual(eventLabel(signedIn), "signedIn")
        XCTAssertEqual(eventLabel(sessionRestored), "sessionRestored")
        XCTAssertEqual(eventLabel(signedOut), "signedOut")
        XCTAssertNotEqual(eventLabel(sessionRestored), eventLabel(signedOut))
        XCTAssertNotEqual(eventLabel(signedIn), eventLabel(signedOut))
    }

    func testStateChangesStreamIsConsumableThroughTheSeam() async {
        var labels: [String] = []
        var restoredSession: SupabaseSession?

        for await event in AuthTestDouble().stateChanges() {
            switch event {
            case .signedIn(let session):
                restoredSession = session
                labels.append("signedIn")
            case .sessionRestored(let session):
                restoredSession = session
                labels.append("sessionRestored")
            case .signedOut:
                labels.append("signedOut")
            }
        }

        XCTAssertEqual(labels, ["sessionRestored", "signedOut"])
        XCTAssertEqual(restoredSession, AuthTestDouble.session)
    }

    private func eventLabel(_ event: SupabaseAuthEvent) -> String {
        switch event {
        case .signedIn:
            return "signedIn"
        case .sessionRestored:
            return "sessionRestored"
        case .signedOut:
            return "signedOut"
        }
    }
}