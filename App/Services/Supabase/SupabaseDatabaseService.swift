import Foundation
import Supabase

actor SupabaseDatabaseService: SupabaseDatabaseAccess {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func select<T: Decodable & Sendable>(
        columns: String,
        from table: String,
        filters: [SupabaseFilter],
        limit: Int?
    ) async throws -> [T] {
        do {
            var query = client.from(table).select(columns)
            for filter in filters {
                query = Self.apply(filter, to: query)
            }
            let builder: PostgrestTransformBuilder = if let limit {
                query.limit(limit)
            } else {
                query
            }
            let response: PostgrestResponse<[T]> = try await builder.execute()
            return response.value
        } catch let error as SupabaseBaseError {
            throw error
        } catch {
            throw SupabaseBaseError.queryFailed
        }
    }

    func rpc<T: Decodable & Sendable>(
        _ function: String,
        arguments: SupabaseRPCArguments?
    ) async throws -> T {
        do {
            let params = arguments.map { $0.values.mapValues(Self.toAnyJSON) } ?? [:]
            let builder = try client.rpc(function, params: params)
            let response: PostgrestResponse<T> = try await builder.execute()
            return response.value
        } catch let error as SupabaseBaseError {
            throw error
        } catch {
            throw SupabaseBaseError.rpcFailed
        }
    }

    func rpcVoid(
        _ function: String,
        arguments: SupabaseRPCArguments?
    ) async throws {
        do {
            let params = arguments.map { $0.values.mapValues(Self.toAnyJSON) } ?? [:]
            let builder = try client.rpc(function, params: params)
            let _: PostgrestResponse<Void> = try await builder.execute()
        } catch let error as SupabaseBaseError {
            throw error
        } catch {
            throw SupabaseBaseError.rpcFailed
        }
    }

    private static func apply(
        _ filter: SupabaseFilter,
        to builder: PostgrestFilterBuilder
    ) -> PostgrestFilterBuilder {
        switch filter.`operator` {
        case .eq:
            return builder.eq(filter.column, value: filter.value)
        case .neq:
            return builder.neq(filter.column, value: filter.value)
        case .gt:
            return builder.gt(filter.column, value: filter.value)
        case .gte:
            return builder.gte(filter.column, value: filter.value)
        case .lt:
            return builder.lt(filter.column, value: filter.value)
        case .lte:
            return builder.lte(filter.column, value: filter.value)
        }
    }

    private static func toAnyJSON(_ value: SupabaseJSONValue) -> AnyJSON {
        switch value {
        case let .string(string):
            return .string(string)
        case let .double(double):
            return .double(double)
        case let .int(int):
            return .integer(int)
        case let .bool(bool):
            return .bool(bool)
        case .null:
            return .null
        }
    }
}