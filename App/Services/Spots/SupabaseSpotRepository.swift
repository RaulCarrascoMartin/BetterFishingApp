import Foundation

actor SupabaseSpotRepository: SpotRepository {
    private let database: any SupabaseDatabaseAccess
    private let auth: any SupabaseAuthProviding

    init(database: any SupabaseDatabaseAccess, auth: any SupabaseAuthProviding) {
        self.database = database
        self.auth = auth
    }

    func listSpots(region: SpotRegion) async throws -> [Spot] {
        let filters = Self.regionBoxFilters(for: region)
        do {
            let spots: [Spot] = try await database.select(
                columns: Self.spotColumns,
                from: "spots",
                filters: filters,
                limit: nil
            )
            return spots
        } catch {
            throw Self.queryFailed(error, operation: "listSpots")
        }
    }

    func nearbySpots(from coordinate: LocationCoordinate2D, radiusKilometers: Double) async throws -> [Spot] {
        let arguments = SupabaseRPCArguments([
            "lat": .double(coordinate.latitude),
            "lng": .double(coordinate.longitude),
            "radius_km": .double(radiusKilometers),
        ])
        do {
            let rows: [NearbySpotRow] = try await database.rpc("nearby_spots", arguments: arguments)
            return rows.map(\.spot)
        } catch {
            throw Self.queryFailed(error, operation: "nearbySpots")
        }
    }

    func spot(id: UUID) async throws -> Spot? {
        do {
            let spots: [Spot] = try await database.select(
                columns: Self.spotColumns,
                from: "spots",
                filters: [SupabaseFilter(column: "id", operator: .eq, value: id.uuidString)],
                limit: 1
            )
            return spots.first
        } catch {
            throw Self.queryFailed(error, operation: "spot")
        }
    }

    func favoriteSpotIDs() async throws -> Set<UUID> {
        guard await auth.currentUser() != nil else {
            return []
        }
        do {
            let rows: [FavoriteIDRow] = try await database.rpc("my_favorite_spot_ids", arguments: nil)
            return Set(rows.map(\.spotID))
        } catch {
            throw Self.queryFailed(error, operation: "favoriteSpotIDs")
        }
    }

    func favoriteSpots() async throws -> [Spot] {
        do {
            let spots: [Spot] = try await database.rpc("my_favorite_spots", arguments: nil)
            return spots
        } catch {
            throw Self.queryFailed(error, operation: "favoriteSpots")
        }
    }

    func setFavorite(spotID: UUID, isFavorite: Bool) async throws {
        guard await auth.currentUser() != nil else {
            throw SpotRepositoryError.authenticationRequired
        }
        let function = isFavorite ? "add_spot_favorite" : "remove_spot_favorite"
        do {
            try await database.rpcVoid(
                function,
                arguments: SupabaseRPCArguments(["spot_id": .string(spotID.uuidString)])
            )
        } catch {
            throw Self.queryFailed(error, operation: function)
        }
    }

    private static let spotColumns = "id,name,category,summary,longitude,latitude"

    private static func regionBoxFilters(for region: SpotRegion) -> [SupabaseFilter] {
        [
            SupabaseFilter(column: "longitude", operator: .gte, value: String(region.minLongitude)),
            SupabaseFilter(column: "longitude", operator: .lte, value: String(region.maxLongitude)),
            SupabaseFilter(column: "latitude", operator: .gte, value: String(region.minLatitude)),
            SupabaseFilter(column: "latitude", operator: .lte, value: String(region.maxLatitude)),
        ]
    }

    private static func queryFailed(_ error: Error, operation: String) -> SpotRepositoryError {
        let reason = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return .queryFailed("\(operation): \(reason)")
    }
}

private struct NearbySpotRow: Decodable, Sendable {
    let id: UUID
    let name: String
    let category: SpotCategory
    let summary: String
    let longitude: Double
    let latitude: Double
    let distanceMeters: Double

    enum CodingKeys: String, CodingKey {
        case id, name, category, summary, longitude, latitude
        case distanceMeters = "distance_m"
    }

    var spot: Spot {
        Spot(
            id: id,
            name: name,
            category: category,
            summary: summary,
            longitude: longitude,
            latitude: latitude,
            distanceMeters: distanceMeters
        )
    }
}

private struct FavoriteIDRow: Decodable, Sendable {
    let spotID: UUID

    enum CodingKeys: String, CodingKey {
        case spotID = "spot_id"
    }
}
