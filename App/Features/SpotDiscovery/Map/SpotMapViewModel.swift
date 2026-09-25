import Foundation
import Observation

@MainActor
@Observable
final class SpotMapViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed
        case unavailable
    }

    enum NearbyNotice: Equatable {
        case permissionDenied
        case noLocation
        case noSpotsInRadius
        case loadFailed
    }

    static let defaultRadiusKilometers = 25.0
    static let defaultRegion = SpotRegion(
        center: LocationCoordinate2D(latitude: 41.3809, longitude: 2.1228),
        latitudinalMeters: 100_000,
        longitudinalMeters: 100_000
    )
    static let unavailableMessage = "El mapa de spots no está disponible"
    static let loadFailedMessage = "No se pudieron cargar los spots"
    static let nearbyFailedMessage = "No se pudieron obtener los spots cercanos"
    static let permissionDeniedMessage = "Permiso de ubicación denegado"
    static let noLocationMessage = "No se pudo obtener tu ubicación"
    static let noSpotsInRadiusMessage = "No hay spots cercanos en este radio"

    private(set) var state: State
    private(set) var spots: [Spot] = []
    private(set) var region: SpotRegion
    private(set) var nearbyNotice: NearbyNotice?
    private(set) var selectedSpot: Spot?
    private(set) var favoriteSpotIDs: Set<UUID> = []

    var nearbyMessage: String? {
        switch nearbyNotice {
        case .permissionDenied: Self.permissionDeniedMessage
        case .noLocation: Self.noLocationMessage
        case .noSpotsInRadius: Self.noSpotsInRadiusMessage
        case .loadFailed: Self.nearbyFailedMessage
        case nil: nil
        }
    }

    private let repository: (any SpotRepository)?
    private let locationProvider: any DeviceLocationProviding
    private let auth: (any SupabaseAuthProviding)?
    private let debounceInterval: Duration

    @ObservationIgnored
    nonisolated(unsafe) private(set) var regionLoadTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private(set) var stateChangesTask: Task<Void, Never>?
    @ObservationIgnored
    private var loadGeneration = 0

    init(
        repository: (any SpotRepository)?,
        locationProvider: any DeviceLocationProviding,
        auth: (any SupabaseAuthProviding)? = nil,
        region: SpotRegion = SpotMapViewModel.defaultRegion,
        debounceInterval: Duration = .milliseconds(400)
    ) {
        self.repository = repository
        self.locationProvider = locationProvider
        self.auth = auth
        self.region = region
        self.debounceInterval = debounceInterval
        self.state = repository == nil ? .unavailable : .loading
    }

    func isFavorite(_ spot: Spot) -> Bool {
        favoriteSpotIDs.contains(spot.id)
    }

    func loadSpots() async {
        regionLoadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        guard let repository else {
            state = .unavailable
            return
        }
        await performRegionLoad(generation: generation, repository: repository)
        await refreshFavoriteSpotIDs()
        if stateChangesTask == nil {
            stateChangesTask = observeAuthStateChanges()
        }
    }

    func updateRegion(_ newRegion: SpotRegion) {
        guard repository != nil, newRegion != region else { return }
        region = newRegion
        scheduleRegionLoad()
    }

    func showNearby() async {
        nearbyNotice = nil
        guard let repository else {
            state = .unavailable
            return
        }
        guard await locationProvider.requestPermissionIfNeeded() else {
            nearbyNotice = .permissionDenied
            return
        }
        guard let coordinate = await locationProvider.currentLocation() else {
            nearbyNotice = .noLocation
            return
        }
        do {
            let nearby = try await repository.nearbySpots(
                from: coordinate,
                radiusKilometers: Self.defaultRadiusKilometers
            )
            if nearby.isEmpty {
                nearbyNotice = .noSpotsInRadius
            } else {
                spots = nearby
                state = .loaded
            }
        } catch {
            nearbyNotice = .loadFailed
        }
        await refreshFavoriteSpotIDs()
    }

    func select(_ spot: Spot) {
        selectedSpot = spot
    }

    func clearSelection() {
        selectedSpot = nil
    }

    func dismissNearbyNotice() {
        nearbyNotice = nil
    }

    private func scheduleRegionLoad() {
        regionLoadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        regionLoadTask = Task { [weak self] in
            guard let self, let repository = self.repository else { return }
            do {
                try await Task.sleep(for: self.debounceInterval)
            } catch {
                return
            }
            await self.performRegionLoad(generation: generation, repository: repository)
        }
    }

    private func performRegionLoad(generation: Int, repository: any SpotRepository) async {
        guard generation == loadGeneration else { return }
        state = .loading
        do {
            let loaded = try await repository.listSpots(region: region)
            guard generation == loadGeneration else { return }
            spots = loaded
            state = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            state = .failed
        }
    }

    private func refreshFavoriteSpotIDs() async {
        guard let repository, let auth, await auth.currentUser() != nil else {
            return
        }
        do {
            favoriteSpotIDs = try await repository.favoriteSpotIDs()
        } catch {
            // El mapa sigue legible sin favoritos; no toca state ni spots.
        }
    }

    private func observeAuthStateChanges() -> Task<Void, Never>? {
        guard let auth else { return nil }
        return Task { [weak self] in
            for await event in auth.stateChanges() {
                guard let self else { return }
                switch event {
                case .signedIn, .sessionRestored:
                    await self.refreshFavoriteSpotIDs()
                case .signedOut:
                    self.favoriteSpotIDs = []
                }
            }
        }
    }

    deinit {
        regionLoadTask?.cancel()
        stateChangesTask?.cancel()
    }
}