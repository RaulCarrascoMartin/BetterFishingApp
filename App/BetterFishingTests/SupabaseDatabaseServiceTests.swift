import XCTest
import Supabase
@testable import BetterFishing

private struct DatabaseTestRow: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

private struct DistanceEstimate: Codable, Equatable, Sendable {
    let distanceKM: Double

    enum CodingKeys: String, CodingKey {
        case distanceKM = "distance_km"
    }
}

final class SupabaseDatabaseServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        HTTPStubRegistry.shared.reset()
    }

    func testSelectDecodesArrayAndAppliesFilterAndLimit() async throws {
        let expectedURL = Self.selectURL(
            for: "spots",
            queryItems: [
                ("select", "id,name"),
                ("species", "eq.bass"),
                ("limit", "10"),
            ]
        )
        HTTPStubRegistry.shared.register(
            .json([
                ["id": 1, "name": "Bass Bay"],
                ["id": 2, "name": "Trout Creek"],
            ]),
            for: expectedURL
        )

        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        let rows: [DatabaseTestRow] = try await db.select(
            columns: "id,name",
            from: "spots",
            filters: [SupabaseFilter(column: "species", operator: .eq, value: "bass")],
            limit: 10
        )

        XCTAssertEqual(
            rows,
            [DatabaseTestRow(id: 1, name: "Bass Bay"), DatabaseTestRow(id: 2, name: "Trout Creek")]
        )
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: expectedURL), 1)
    }

    func testSelectWithMultipleFiltersAndNoLimitBuildsEveryOperator() async throws {
        let expectedURL = Self.selectURL(
            for: "catches",
            queryItems: [
                ("select", "id,species,weight"),
                ("species", "eq.bass"),
                ("angler", "neq.anon"),
                ("min_size", "gte.30"),
                ("depth", "lt.50"),
                ("rating", "gt.4"),
                ("area_km2", "lte.900"),
            ]
        )
        HTTPStubRegistry.shared.register(.json([]), for: expectedURL)

        let db: any SupabaseDatabaseAccess = try makeDatabaseService()
        let filters: [SupabaseFilter] = [
            SupabaseFilter(column: "species", operator: .eq, value: "bass"),
            SupabaseFilter(column: "angler", operator: .neq, value: "anon"),
            SupabaseFilter(column: "min_size", operator: .gte, value: "30"),
            SupabaseFilter(column: "depth", operator: .lt, value: "50"),
            SupabaseFilter(column: "rating", operator: .gt, value: "4"),
            SupabaseFilter(column: "area_km2", operator: .lte, value: "900"),
        ]

        let rows: [DatabaseTestRow] = try await db.select(
            columns: "id,species,weight",
            from: "catches",
            filters: filters,
            limit: nil
        )

        XCTAssertEqual(rows, [])
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: expectedURL), 1)
    }

    func testRPCReturnsDecodedValueAndEncodesArgumentsAsJSON() async throws {
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/estimate_distance"
        HTTPStubRegistry.shared.register(
            .json(["distance_km": 42.5]),
            for: rpcURL
        )

        let db: any SupabaseDatabaseAccess = try makeDatabaseService()
        let arguments = SupabaseRPCArguments([
            "name": .string("Madrid"),
            "count": .int(3),
            "ratio": .double(4.5),
            "active": .bool(true),
            "missing": .null,
        ])

        let result: DistanceEstimate = try await db.rpc("estimate_distance", arguments: arguments)

        XCTAssertEqual(result, DistanceEstimate(distanceKM: 42.5))
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: rpcURL), 1)

        let bodies = HTTPStubRegistry.shared.requestBodies(for: rpcURL)
        XCTAssertEqual(bodies.count, 1)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.first)) as? [String: Any]
        )
        XCTAssertEqual(json["name"] as? String, "Madrid")
        XCTAssertEqual(json["count"] as? Int, 3)
        XCTAssertEqual(json["ratio"] as? Double, 4.5)
        XCTAssertEqual(json["active"] as? Bool, true)
        XCTAssertTrue(json["missing"] is NSNull)
    }

    func testRPCVoidAcceptsNoContentResponse() async throws {
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/clear_cache"
        HTTPStubRegistry.shared.register(
            HTTPStub(
                statusCode: 204,
                data: Data(),
                headers: ["Content-Type": "application/json"]
            ),
            for: rpcURL
        )

        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        try await db.rpcVoid("clear_cache", arguments: nil)

        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: rpcURL), 1)
    }

    func testRPCVoidAcceptsCreatedStatus() async throws {
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/create_cache"
        HTTPStubRegistry.shared.register(
            .json(["created": true], statusCode: 201),
            for: rpcURL
        )

        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        try await db.rpcVoid("create_cache", arguments: nil)

        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: rpcURL), 1)
    }

    func testRPCVoidIgnoresUnexpectedJSONBody() async throws {
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/clear_cache"
        HTTPStubRegistry.shared.register(
            .json(["unexpected": ["nested": true]]),
            for: rpcURL
        )

        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        try await db.rpcVoid("clear_cache", arguments: nil)

        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: rpcURL), 1)
    }

    func testRPCVoidEncodesTypedArgumentsAndSendsOneRequest() async throws {
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/upsert_value"
        HTTPStubRegistry.shared.register(
            HTTPStub(statusCode: 200, data: Data(), headers: ["Content-Type": "application/json"]),
            for: rpcURL
        )
        let arguments = SupabaseRPCArguments([
            "name": .string("angler"),
            "count": .int(3),
            "ratio": .double(4.5),
            "active": .bool(true),
            "missing": .null,
        ])
        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        try await db.rpcVoid("upsert_value", arguments: arguments)

        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: rpcURL), 1)
        let body = try XCTUnwrap(HTTPStubRegistry.shared.requestBodies(for: rpcURL).first)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["name"] as? String, "angler")
        XCTAssertEqual(json["count"] as? Int, 3)
        XCTAssertEqual(json["ratio"] as? Double, 4.5)
        XCTAssertEqual(json["active"] as? Bool, true)
        XCTAssertTrue(json["missing"] is NSNull)
    }

    func testRPCVoidWithTransportErrorThrowsRPCFailed() async throws {
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/clear_cache"
        HTTPStubRegistry.shared.register(
            HTTPStub(error: URLError(.networkConnectionLost)),
            for: rpcURL
        )
        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        do {
            try await db.rpcVoid("clear_cache", arguments: nil)
            XCTFail("Expected rpcVoid to throw")
        } catch let error as SupabaseBaseError {
            XCTAssertEqual(error, .rpcFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRPCVoidWithClientErrorThrowsRPCFailed() async throws {
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/clear_cache"
        HTTPStubRegistry.shared.register(
            .json(["message": "invalid request"], statusCode: 400),
            for: rpcURL
        )
        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        do {
            try await db.rpcVoid("clear_cache", arguments: nil)
            XCTFail("Expected rpcVoid to throw")
        } catch let error as SupabaseBaseError {
            XCTAssertEqual(error, .rpcFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRPCVoidWithServerErrorThrowsRPCFailed() async throws {
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/clear_cache"
        HTTPStubRegistry.shared.register(
            .json(["message": "temporarily unavailable"], statusCode: 503),
            for: rpcURL
        )
        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        do {
            try await db.rpcVoid("clear_cache", arguments: nil)
            XCTFail("Expected rpcVoid to throw")
        } catch let error as SupabaseBaseError {
            XCTAssertEqual(error, .rpcFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRPCWithEmptyBodyThrowsRPCFailed() async throws {
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/estimate_distance"
        HTTPStubRegistry.shared.register(
            HTTPStub(statusCode: 200, data: Data(), headers: ["Content-Type": "application/json"]),
            for: rpcURL
        )
        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        do {
            let _: DistanceEstimate = try await db.rpc("estimate_distance", arguments: nil)
            XCTFail("Expected rpc to throw")
        } catch let error as SupabaseBaseError {
            XCTAssertEqual(error, .rpcFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSelectWithServerErrorThrowsQueryFailed() async throws {
        let expectedURL = Self.selectURL(
            for: "spots",
            queryItems: [("select", "id,name")]
        )
        HTTPStubRegistry.shared.register(
            .json(["message": "Database hiccup"], statusCode: 500),
            for: expectedURL
        )

        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        do {
            _ = try await db.select(
                columns: "id,name",
                from: "spots",
                filters: [],
                limit: nil
            ) as [DatabaseTestRow]
            XCTFail("Expected select to throw")
        } catch let error as SupabaseBaseError {
            XCTAssertEqual(error, .queryFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRPCWithServerErrorThrowsRPCFailed() async throws {
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/estimate_distance"
        HTTPStubRegistry.shared.register(
            .json(["message": "function not found"], statusCode: 404),
            for: rpcURL
        )

        let db: any SupabaseDatabaseAccess = try makeDatabaseService()

        do {
            _ = try await db.rpc("estimate_distance", arguments: nil) as DistanceEstimate
            XCTFail("Expected rpc to throw")
        } catch let error as SupabaseBaseError {
            XCTAssertEqual(error, .rpcFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private func makeDatabaseService() throws -> SupabaseDatabaseService {
        let supabaseURL = try XCTUnwrap(URL(string: "https://project-ref.supabase.co"))
        let options = SupabaseClientOptions(
            auth: .init(storage: InMemoryAuthLocalStorage(), autoRefreshToken: false),
            global: .init(session: .mockSession())
        )
        let client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: "test-anon-key",
            options: options
        )
        return SupabaseDatabaseService(client: client)
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