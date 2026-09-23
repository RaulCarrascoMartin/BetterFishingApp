import Foundation

protocol SupabaseDatabaseAccess: Sendable {
    func select<T: Decodable & Sendable>(
        columns: String,
        from table: String,
        filters: [SupabaseFilter],
        limit: Int?
    ) async throws -> [T]
    func rpc<T: Decodable & Sendable>(
        _ function: String,
        arguments: SupabaseRPCArguments?
    ) async throws -> T
}

struct SupabaseFilter: Equatable, Sendable {
    let column: String
    let `operator`: SupabaseFilterOperator
    let value: String
}

enum SupabaseFilterOperator: String, Sendable {
    case eq, neq, gt, gte, lt, lte
}

struct SupabaseRPCArguments: Equatable, Sendable {
    var values: [String: SupabaseJSONValue]

    init(_ values: [String: SupabaseJSONValue]) {
        self.values = values
    }
}

enum SupabaseJSONValue: Equatable, Sendable {
    case string(String)
    case double(Double)
    case int(Int)
    case bool(Bool)
    case null
}