import Foundation

@testable import BetterFishing

/// Doble del repositorio de spots: éxito/fallo programables y registro de llamadas para aserciones.
/// Sigue el patrón de `SupabaseBaseFake` (clase `@unchecked Sendable` protegida por `NSLock`).
final class SpotRepositoryFake: SpotRepository, @unchecked Sendable {
    struct RecordedFavoriteToggle: Equatable {
        let spotID: UUID
        let isFavorite: Bool
    }

    struct RegionSeed: Equatable {
        let region: SpotRegion
        let spots: [Spot]
    }

    private struct State {
        var regionSeeds: [RegionSeed] = []
        var nearbyResult: [Spot] = []
        var favoriteIDs: Set<UUID> = []
        var listSpotsError: SpotRepositoryError?
        var nearbySpotsError: SpotRepositoryError?
        var spotError: SpotRepositoryError?
        var favoriteSpotIDsError: SpotRepositoryError?
        var favoriteSpotsError: SpotRepositoryError?
        var setFavoriteError: SpotRepositoryError?
        var recordedRegions: [SpotRegion] = []
        var recordedCoordinates: [LocationCoordinate2D] = []
        var recordedRadii: [Double] = []
        var recordedSpotIDs: [UUID] = []
        var recordedFavoriteToggles: [RecordedFavoriteToggle] = []
    }

    private let lock = NSLock()
    private var state: State

    init() {
        state = State()
    }

    var regionSeeds: [RegionSeed] {
        get { withLock { state.regionSeeds } }
        set { withLock { state.regionSeeds = newValue } }
    }

    var nearbyResult: [Spot] {
        get { withLock { state.nearbyResult } }
        set { withLock { state.nearbyResult = newValue } }
    }

    var favoriteIDs: Set<UUID> {
        get { withLock { state.favoriteIDs } }
        set { withLock { state.favoriteIDs = newValue } }
    }

    var listSpotsError: SpotRepositoryError? {
        get { withLock { state.listSpotsError } }
        set { withLock { state.listSpotsError = newValue } }
    }

    var nearbySpotsError: SpotRepositoryError? {
        get { withLock { state.nearbySpotsError } }
        set { withLock { state.nearbySpotsError = newValue } }
    }

    var spotError: SpotRepositoryError? {
        get { withLock { state.spotError } }
        set { withLock { state.spotError = newValue } }
    }

    var favoriteSpotIDsError: SpotRepositoryError? {
        get { withLock { state.favoriteSpotIDsError } }
        set { withLock { state.favoriteSpotIDsError = newValue } }
    }

    var favoriteSpotsError: SpotRepositoryError? {
        get { withLock { state.favoriteSpotsError } }
        set { withLock { state.favoriteSpotsError = newValue } }
    }

    var setFavoriteError: SpotRepositoryError? {
        get { withLock { state.setFavoriteError } }
        set { withLock { state.setFavoriteError = newValue } }
    }

    var recordedRegions: [SpotRegion] {
        withLock { state.recordedRegions }
    }

    var recordedCoordinates: [LocationCoordinate2D] {
        withLock { state.recordedCoordinates }
    }

    var recordedRadii: [Double] {
        withLock { state.recordedRadii }
    }

    var recordedSpotIDs: [UUID] {
        withLock { state.recordedSpotIDs }
    }

    var recordedFavoriteToggles: [RecordedFavoriteToggle] {
        withLock { state.recordedFavoriteToggles }
    }

    var allSeededSpots: [Spot] {
        withLock { state.regionSeeds.flatMap(\.spots) }
    }

    func seed(_ spots: [Spot], for region: SpotRegion) {
        withLock {
            if let index = state.regionSeeds.firstIndex(where: { $0.region == region }) {
                state.regionSeeds[index] = RegionSeed(region: region, spots: spots)
            } else {
                state.regionSeeds.append(RegionSeed(region: region, spots: spots))
            }
        }
    }

    func reset() {
        withLock {
            state.recordedRegions = []
            state.recordedCoordinates = []
            state.recordedRadii = []
            state.recordedSpotIDs = []
            state.recordedFavoriteToggles = []
        }
    }

    func listSpots(region: SpotRegion) async throws -> [Spot] {
        let result = withLock { () -> (error: SpotRepositoryError?, spots: [Spot]) in
            state.recordedRegions.append(region)
            let spots = state.regionSeeds.first(where: { $0.region == region })?.spots ?? []
            return (state.listSpotsError, spots)
        }
        if let error = result.error {
            throw error
        }
        return result.spots
    }

    func nearbySpots(from coordinate: LocationCoordinate2D, radiusKilometers: Double) async throws -> [Spot] {
        let result = withLock { () -> (error: SpotRepositoryError?, spots: [Spot]) in
            state.recordedCoordinates.append(coordinate)
            state.recordedRadii.append(radiusKilometers)
            return (state.nearbySpotsError, state.nearbyResult.sorted(by: nearbyOrder))
        }
        if let error = result.error {
            throw error
        }
        return result.spots
    }

    func spot(id: UUID) async throws -> Spot? {
        let result = withLock { () -> (error: SpotRepositoryError?, spot: Spot?) in
            state.recordedSpotIDs.append(id)
            return (state.spotError, state.regionSeeds.flatMap(\.spots).first { $0.id == id })
        }
        if let error = result.error {
            throw error
        }
        return result.spot
    }

    func favoriteSpotIDs() async throws -> Set<UUID> {
        let result = withLock { () -> (error: SpotRepositoryError?, ids: Set<UUID>) in
            (state.favoriteSpotIDsError, state.favoriteIDs)
        }
        if let error = result.error {
            throw error
        }
        return result.ids
    }

    func favoriteSpots() async throws -> [Spot] {
        let result = withLock { () -> (error: SpotRepositoryError?, spots: [Spot]) in
            let favorites = state.regionSeeds.flatMap(\.spots).filter { state.favoriteIDs.contains($0.id) }
            return (state.favoriteSpotsError, favorites)
        }
        if let error = result.error {
            throw error
        }
        return result.spots
    }

    func setFavorite(spotID: UUID, isFavorite: Bool) async throws {
        let error = withLock { () -> SpotRepositoryError? in
            state.recordedSpotIDs.append(spotID)
            state.recordedFavoriteToggles.append(RecordedFavoriteToggle(spotID: spotID, isFavorite: isFavorite))
            return state.setFavoriteError
        }
        if let error {
            throw error
        }
        withLock {
            if isFavorite {
                state.favoriteIDs.insert(spotID)
            } else {
                state.favoriteIDs.remove(spotID)
            }
        }
    }

    private func nearbyOrder(_ lhs: Spot, _ rhs: Spot) -> Bool {
        switch (lhs.distanceMeters, rhs.distanceMeters) {
        case let (left?, right?):
            return left < right
        case (_, nil):
            return true
        case (nil, _):
            return false
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}