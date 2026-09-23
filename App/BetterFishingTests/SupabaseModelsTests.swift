import Foundation
import XCTest

@testable import BetterFishing

final class SupabaseModelsTests: XCTestCase {
    func testUserRoundTripWithEmailPresentPreservesAllFields() throws {
        let user = try makeUser(email: "angler@example.com")

        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(SupabaseUser.self, from: data)

        XCTAssertEqual(decoded, user)
        XCTAssertEqual(decoded.id, user.id)
        XCTAssertEqual(decoded.email, "angler@example.com")
        XCTAssertEqual(decoded.createdAt, user.createdAt)
    }

    func testUserRoundTripWithEmailAbsentPreservesNil() throws {
        let user = try makeUser(email: nil)

        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(SupabaseUser.self, from: data)

        XCTAssertEqual(decoded, user)
        XCTAssertNil(decoded.email)
    }

    func testSessionRoundTripPreservesAllFields() throws {
        let session = try makeSession()

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SupabaseSession.self, from: data)

        XCTAssertEqual(decoded, session)
        XCTAssertEqual(decoded.accessToken, session.accessToken)
        XCTAssertEqual(decoded.refreshToken, session.refreshToken)
        XCTAssertEqual(decoded.expiresAt, session.expiresAt)
        XCTAssertEqual(decoded.user, session.user)
    }

    func testEncodedJSONUsesSwiftPropertyNames() throws {
        let session = try makeSession()
        let sessionData = try JSONEncoder().encode(session)

        let sessionObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: sessionData) as? [String: Any]
        )
        XCTAssertEqual(Set(sessionObject.keys), ["accessToken", "refreshToken", "expiresAt", "user"])

        let userObject = try XCTUnwrap(sessionObject["user"] as? [String: Any])
        XCTAssertEqual(Set(userObject.keys), ["id", "email", "createdAt"])
    }

    func testIdentifiableAndEquatableSemantics() throws {
        let user = try makeUser(email: nil)
        let equal = try makeUser(email: nil)
        let different = try makeUser(email: "other@example.com")

        XCTAssertEqual(user, equal)
        XCTAssertNotEqual(different, user)
        XCTAssertEqual(user.id, equal.id)
        XCTAssertEqual(user.id, user.id)
    }

    // MARK: - Helpers

    private func makeUser(email: String?) throws -> SupabaseUser {
        let id = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        return SupabaseUser(
            id: id,
            email: email,
            createdAt: Date(timeIntervalSinceReferenceDate: 7_500_000)
        )
    }

    private func makeSession() throws -> SupabaseSession {
        let user = try makeUser(email: "angler@example.com")
        return SupabaseSession(
            accessToken: "access-token-123",
            refreshToken: "refresh-token-456",
            expiresAt: Date(timeIntervalSinceReferenceDate: 7_500_000 + 3_600),
            user: user
        )
    }
}