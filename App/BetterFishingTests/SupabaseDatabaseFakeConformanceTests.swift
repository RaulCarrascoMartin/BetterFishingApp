import Foundation
import XCTest

@testable import BetterFishing

struct RecordedSelect: Equatable {
    let columns: String
    let table: String
    let filters: [SupabaseFilter]
    let limit: Int?
}

struct RecordedRPC: Equatable {
    let function: String
    let arguments: SupabaseRPCArguments?
}

final class DatabaseRecorderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSelects: [RecordedSelect] = []
    private var recordedRPCs: [RecordedRPC] = []

    var selects: [RecordedSelect] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSelects
    }

    var rpcs: [RecordedRPC] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRPCs
    }

    func recordSelect(_ value: RecordedSelect) {
        lock.lock()
        defer { lock.unlock() }
        recordedSelects.append(value)
    }

    func recordRPC(_ value: RecordedRPC) {
        lock.lock()
        defer { lock.unlock() }
        recordedRPCs.append(value)
    }
}

struct DatabaseTestDoubleError: Error, Equatable {
    let reason: String
}

struct DatabaseTestDouble: SupabaseDatabaseAccess, Sendable {
    private let cannedRows: [String]
    private let cannedValue: String
    private let recorder: DatabaseRecorderBox

    init(
        cannedRows: [String] = [],
        cannedValue: String = "",
        recorder: DatabaseRecorderBox = DatabaseRecorderBox()
    ) {
        self.cannedRows = cannedRows
        self.cannedValue = cannedValue
        self.recorder = recorder
    }

    var recordedSelects: [RecordedSelect] {
        recorder.selects
    }

    var recordedRPCs: [RecordedRPC] {
        recorder.rpcs
    }

    func select<T: Decodable & Sendable>(
        columns: String,
        from table: String,
        filters: [SupabaseFilter],
        limit: Int?
    ) async throws -> [T] {
        recorder.recordSelect(
            RecordedSelect(columns: columns, table: table, filters: filters, limit: limit)
        )
        return cannedRows.compactMap { $0 as? T }
    }

    func rpc<T: Decodable & Sendable>(
        _ function: String,
        arguments: SupabaseRPCArguments?
    ) async throws -> T {
        recorder.recordRPC(RecordedRPC(function: function, arguments: arguments))
        guard let value = cannedValue as? T else {
            throw DatabaseTestDoubleError(reason: "rpc type mismatch")
        }
        return value
    }

    func rpcVoid(
        _ function: String,
        arguments: SupabaseRPCArguments?
    ) async throws {
        recorder.recordRPC(RecordedRPC(function: function, arguments: arguments))
    }
}

final class SupabaseDatabaseFakeConformanceTests: XCTestCase {
    func testDatabaseTestDoubleUsableAsAnySupabaseDatabaseAccessAndRecordsSelect() async throws {
        let filters: [SupabaseFilter] = [
            SupabaseFilter(column: "species", operator: .eq, value: "bass"),
            SupabaseFilter(column: "min_size", operator: .gte, value: "30"),
        ]
        let double = DatabaseTestDouble(cannedRows: ["row-1", "row-2"])
        let db: any SupabaseDatabaseAccess = double

        let rows: [String] = try await db.select(
            columns: "id,species",
            from: "spots",
            filters: filters,
            limit: 10
        )

        XCTAssertEqual(rows, ["row-1", "row-2"])
        let recorded = double.recordedSelects
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.columns, "id,species")
        XCTAssertEqual(recorded.first?.table, "spots")
        XCTAssertEqual(recorded.first?.filters, filters)
        XCTAssertEqual(recorded.first?.limit, 10)
    }

    func testDatabaseTestDoubleRecordsRPCFunctionAndArguments() async throws {
        let arguments = SupabaseRPCArguments([
            "lat": .double(40.4168),
            "lng": .double(-3.7038),
            "radius": .int(5),
        ])
        let double = DatabaseTestDouble(cannedValue: "ok")
        let db: any SupabaseDatabaseAccess = double

        let result: String = try await db.rpc("nearby_spots", arguments: arguments)

        XCTAssertEqual(result, "ok")
        let recorded = double.recordedRPCs
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.function, "nearby_spots")
        XCTAssertEqual(recorded.first?.arguments, arguments)
    }

    func testDatabaseTestDoubleRecordsRPCVoidFunctionAndArguments() async throws {
        let arguments = SupabaseRPCArguments([
            "id": .string("value-1"),
            "active": .bool(true),
        ])
        let double = DatabaseTestDouble()
        let db: any SupabaseDatabaseAccess = double

        try await db.rpcVoid("mutate_value", arguments: arguments)

        let recorded = double.recordedRPCs
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.function, "mutate_value")
        XCTAssertEqual(recorded.first?.arguments, arguments)
    }

    func testSupabaseFilterOperatorRawValuesAndEquality() {
        XCTAssertEqual(
            SupabaseFilterOperator.eq.rawValue,
            "eq"
        )
        XCTAssertEqual(SupabaseFilterOperator(rawValue: "gte"), .gte)
        XCTAssertNil(SupabaseFilterOperator(rawValue: "invalid"))
        let filter = SupabaseFilter(column: "depth", operator: .lt, value: "50")
        XCTAssertEqual(filter.`operator`.rawValue, "lt")
        XCTAssertEqual(
            filter,
            SupabaseFilter(column: "depth", operator: .lt, value: "50")
        )
        XCTAssertNotEqual(
            filter,
            SupabaseFilter(column: "depth", operator: .lte, value: "50")
        )
        XCTAssertNotEqual(
            filter,
            SupabaseFilter(column: "depth", operator: .lt, value: "51")
        )
    }

    func testSupabaseJSONValueCasesEquate() {
        XCTAssertEqual(SupabaseJSONValue.string("a"), .string("a"))
        XCTAssertNotEqual(SupabaseJSONValue.string("a"), .string("b"))
        XCTAssertEqual(SupabaseJSONValue.double(1.5), .double(1.5))
        XCTAssertNotEqual(SupabaseJSONValue.int(3), .double(3))
        XCTAssertEqual(SupabaseJSONValue.int(3), .int(3))
        XCTAssertEqual(SupabaseJSONValue.bool(true), .bool(true))
        XCTAssertNotEqual(SupabaseJSONValue.bool(true), .bool(false))
        XCTAssertEqual(SupabaseJSONValue.null, .null)
    }

    func testSupabaseRPCArgumentsInitFromDictionary() {
        let arguments = SupabaseRPCArguments([
            "name": .string("Madrid"),
            "count": .int(3),
            "active": .bool(true),
            "missing": .null,
        ])

        XCTAssertEqual(arguments.values.count, 4)
        XCTAssertEqual(arguments.values["name"], .string("Madrid"))
        XCTAssertEqual(arguments.values["count"], .int(3))
        XCTAssertEqual(arguments.values["active"], .bool(true))
        XCTAssertEqual(arguments.values["missing"], .null)
        XCTAssertEqual(arguments, SupabaseRPCArguments(arguments.values))
    }
}