import Foundation

protocol SpotRepository: Sendable {
    func listSpots(region: SpotRegion) async throws -> [Spot]
    func nearbySpots(from coordinate: LocationCoordinate2D, radiusKilometers: Double) async throws -> [Spot]
    func spot(id: UUID) async throws -> Spot?
    func favoriteSpotIDs() async throws -> Set<UUID>
    func favoriteSpots() async throws -> [Spot]
    func setFavorite(spotID: UUID, isFavorite: Bool) async throws
}

enum SpotRepositoryError: Error, Sendable, Equatable {
    case backendUnavailable
    case queryFailed(String)
    case authenticationRequired
}