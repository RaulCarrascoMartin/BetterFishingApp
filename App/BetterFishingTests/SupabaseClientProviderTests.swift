import XCTest
import Supabase
@testable import BetterFishing

private struct ProviderTestRow: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

final class SupabaseClientProviderTests: XCTestCase {
    private let tokenURL = "https://project-ref.supabase.co/auth/v1/token?grant_type=password"
    private let uploadURL =
        "https://project-ref.supabase.co/storage/v1/object/catches/2026/season/catch-1.jpg"
    private let anonKey = "test-anon-key"

    override func setUp() {
        super.setUp()
        HTTPStubRegistry.shared.reset()
    }

    func testMakeStackReturnsExpectedActorTypesForValidConfiguration() throws {
        let stack = try makeProvider().makeStack(options: makeOptions())

        XCTAssertNotNil(stack.auth)
        XCTAssertNotNil(stack.storage)
        XCTAssertNotNil(stack.database)
        XCTAssertTrue(stack.auth is SupabaseAuthService)
        XCTAssertTrue(stack.storage is SupabaseStorageService)
        XCTAssertTrue(stack.database is SupabaseDatabaseService)
    }

    func testMakeStackSharesSingleClientAcrossAuthStorageAndDatabaseSeams() async throws {
        let selectURL = Self.selectURL(for: "spots", queryItems: [("select", "id,name")])

        HTTPStubRegistry.shared.register(.json(Self.sessionJSON), for: tokenURL)
        HTTPStubRegistry.shared.register(
            .json([
                ["id": 1, "name": "Bass Bay"],
                ["id": 2, "name": "Trout Creek"],
            ]),
            for: selectURL
        )
        HTTPStubRegistry.shared.register(
            .json([
                "Key": "catches/2026/season/catch-1.jpg",
                "Id": "6f1d2c3b-8f2e-4a11-9e2e-0a1b2c3d4e5f",
            ]),
            for: uploadURL
        )

        let stack = try makeProvider().makeStack(options: makeOptions())

        let session = try await stack.auth.signIn(
            email: "angler@example.com",
            password: "correct-horse"
        )
        let rows: [ProviderTestRow] = try await stack.database.select(
            columns: "id,name",
            from: "spots",
            filters: [],
            limit: nil
        )
        let storedPath = try await stack.storage.upload(
            bucket: "catches",
            path: "2026/season/catch-1.jpg",
            data: Data([0xFF, 0xD8, 0xFF]),
            options: nil
        )

        XCTAssertEqual(session.accessToken, "access-token-111")
        XCTAssertEqual(
            rows,
            [ProviderTestRow(id: 1, name: "Bass Bay"), ProviderTestRow(id: 2, name: "Trout Creek")]
        )
        XCTAssertEqual(storedPath, "catches/2026/season/catch-1.jpg")
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: tokenURL), 1)
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: selectURL), 1)
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: uploadURL), 1)

        let selectHeaders = HTTPStubRegistry.shared.requestHeaders(for: selectURL).first ?? [:]
        let authorization = selectHeaders.first { $0.key.lowercased() == "authorization" }?.value
        XCTAssertEqual(authorization, "Bearer access-token-111")
    }

    func testMakeStackThrowsInvalidProjectURLWhenURLHasNoHost() throws {
        let invalidURL = try XCTUnwrap(URL(string: "http://"))
        let provider = SupabaseClientProvider(
            configuration: SupabaseClientConfiguration(projectURL: invalidURL, anonKey: anonKey)
        )

        XCTAssertThrowsError(try provider.makeStack()) { error in
            XCTAssertEqual(error as? SupabaseBaseError, .invalidProjectURL)
        }
    }

    func testMakeStackThrowsInvalidProjectURLWhenSchemeIsNotHTTP() throws {
        let invalidURL = try XCTUnwrap(URL(string: "ftp://project-ref.supabase.co"))
        let provider = SupabaseClientProvider(
            configuration: SupabaseClientConfiguration(projectURL: invalidURL, anonKey: anonKey)
        )

        XCTAssertThrowsError(try provider.makeStack()) { error in
            XCTAssertEqual(error as? SupabaseBaseError, .invalidProjectURL)
        }
    }

    func testMakeClientBuildsClientFromConfiguration() throws {
        let client = try makeProvider().makeClient(options: makeOptions())

        let authorization = client.headers.first { $0.key.lowercased() == "authorization" }?.value
        XCTAssertEqual(authorization, "Bearer \(anonKey)")
        let apiKey = client.headers.first { $0.key.lowercased() == "apikey" }?.value
        XCTAssertEqual(apiKey, anonKey)
    }

    private func makeProvider() throws -> SupabaseClientProvider {
        let url = try XCTUnwrap(URL(string: "https://project-ref.supabase.co"))
        return SupabaseClientProvider(
            configuration: SupabaseClientConfiguration(projectURL: url, anonKey: anonKey)
        )
    }

    private func makeOptions() -> SupabaseClientOptions {
        SupabaseClientOptions(
            auth: .init(storage: InMemoryAuthLocalStorage(), autoRefreshToken: false),
            global: .init(session: .mockSession())
        )
    }

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

    private static func selectURL(for table: String, queryItems: [(String, String)]) -> String {
        let query = queryItems
            .map { name, value in "\(escapeQuery(name))=\(escapeQuery(value))" }
            .joined(separator: "&")
        return "https://project-ref.supabase.co/rest/v1/\(table)?\(query)"
    }

    private static func escapeQuery(_ string: String) -> String {
        string.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
                .subtracting(CharacterSet(charactersIn: ":#[]@!$&'()*+,;="))
        ) ?? string
    }
}