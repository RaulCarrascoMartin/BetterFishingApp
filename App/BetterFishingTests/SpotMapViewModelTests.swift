import XCTest

@testable import BetterFishing

@MainActor
private final class MapLocationProviderDouble: DeviceLocationProviding {
    private let granted: Bool
    private let coordinate: LocationCoordinate2D?

    private(set) var permissionRequestCount = 0
    private(set) var locationRequestCount = 0

    init(granted: Bool, coordinate: LocationCoordinate2D?) {
        self.granted = granted
        self.coordinate = coordinate
    }

    func requestPermissionIfNeeded() async -> Bool {
        permissionRequestCount += 1
        return granted
    }

    func currentLocation() async -> LocationCoordinate2D? {
        locationRequestCount += 1
        return granted ? coordinate : nil
    }
}

@MainActor
final class SpotMapViewModelTests: XCTestCase {
    private let coordinate = LocationCoordinate2D(latitude: 41.4, longitude: 2.2)

    private func makeRegion(center: LocationCoordinate2D? = nil) -> SpotRegion {
        SpotRegion(
            center: center ?? LocationCoordinate2D(latitude: 40.5, longitude: 1.0),
            latitudinalMeters: 60_000,
            longitudinalMeters: 60_000
        )
    }

    private func makeSpot(id: UUID = UUID(), name: String = "Spot", distanceMeters: Double? = nil) -> Spot {
        Spot(
            id: id,
            name: name,
            category: .lake,
            summary: "Resumen del spot.",
            longitude: 2.2,
            latitude: 41.4,
            distanceMeters: distanceMeters
        )
    }

    private func makeViewModel(
        repository: SpotRepositoryFake,
        location: MapLocationProviderDouble,
        auth: SupabaseBaseFake? = nil,
        region: SpotRegion? = nil,
        debounce: Duration = .milliseconds(20)
    ) -> SpotMapViewModel {
        SpotMapViewModel(
            repository: repository,
            locationProvider: location,
            auth: auth,
            region: region ?? SpotMapViewModel.defaultRegion,
            debounceInterval: debounce
        )
    }

    func testRegionChangeDebouncesAndLoadsReturnedSpotsForRegion() async {
        let repository = SpotRepositoryFake()
        let region = makeRegion()
        repository.seed([makeSpot(name: "A"), makeSpot(name: "B")], for: region)
        let viewModel = makeViewModel(
            repository: repository,
            location: MapLocationProviderDouble(granted: false, coordinate: nil)
        )

        viewModel.updateRegion(region)
        await viewModel.regionLoadTask?.value

        XCTAssertEqual(viewModel.spots.map(\.name), ["A", "B"])
        XCTAssertEqual(repository.recordedRegions, [region])
        XCTAssertEqual(viewModel.state, .loaded)
    }

    func testRapidRegionChangesOnlyLoadTheLatestRegion() async {
        let repository = SpotRepositoryFake()
        let first = makeRegion(center: LocationCoordinate2D(latitude: 40.0, longitude: 0.0))
        let latest = makeRegion(center: LocationCoordinate2D(latitude: 39.0, longitude: -1.0))
        repository.seed([makeSpot(name: "Latest")], for: latest)
        let viewModel = makeViewModel(
            repository: repository,
            location: MapLocationProviderDouble(granted: false, coordinate: nil)
        )

        viewModel.updateRegion(first)
        viewModel.updateRegion(latest)
        await viewModel.regionLoadTask?.value

        XCTAssertEqual(repository.recordedRegions, [latest])
        XCTAssertEqual(viewModel.spots.map(\.name), ["Latest"])
        XCTAssertEqual(viewModel.region, latest)
        XCTAssertEqual(viewModel.state, .loaded)
    }

    func testRegionLoadErrorShowsRetryableFailedStateAndRetryRecovers() async {
        let repository = SpotRepositoryFake()
        let region = makeRegion()
        repository.seed([makeSpot(name: "A")], for: region)
        repository.listSpotsError = .queryFailed("red caída")
        let viewModel = makeViewModel(
            repository: repository,
            location: MapLocationProviderDouble(granted: false, coordinate: nil)
        )

        viewModel.updateRegion(region)
        await viewModel.regionLoadTask?.value

        XCTAssertEqual(viewModel.state, .failed)
        XCTAssertTrue(viewModel.spots.isEmpty, "El fallo no debe publicar spots")

        repository.listSpotsError = nil
        await viewModel.loadSpots()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.spots.map(\.name), ["A"])
        XCTAssertEqual(repository.recordedRegions, [region, region], "El reintento relanza el listado de la región")
    }

    func testRepositoryNilShowsUnavailableStateWithoutLoadingOrLocationCalls() async {
        let location = MapLocationProviderDouble(granted: true, coordinate: coordinate)
        let viewModel = SpotMapViewModel(repository: nil, locationProvider: location)

        XCTAssertEqual(viewModel.state, .unavailable)

        await viewModel.loadSpots()
        XCTAssertEqual(viewModel.state, .unavailable)

        await viewModel.showNearby()
        XCTAssertEqual(viewModel.state, .unavailable)
        XCTAssertNil(viewModel.nearbyNotice)
        XCTAssertEqual(location.permissionRequestCount, 0, "Sin repositorio no debe pedirse permiso de ubicación")
        XCTAssertEqual(location.locationRequestCount, 0)
    }

    func testShowNearbyWithLocationListsSpotsOrderedByDistance() async {
        let repository = SpotRepositoryFake()
        repository.nearbyResult = [
            makeSpot(name: "Lejano", distanceMeters: 12_000),
            makeSpot(name: "Cercano", distanceMeters: 500),
        ]
        let location = MapLocationProviderDouble(granted: true, coordinate: coordinate)
        let viewModel = makeViewModel(repository: repository, location: location)

        await viewModel.showNearby()

        XCTAssertEqual(viewModel.spots.map(\.name), ["Cercano", "Lejano"])
        XCTAssertEqual(viewModel.spots.map(\.distanceMeters), [500, 12_000])
        XCTAssertNil(viewModel.nearbyNotice)
        XCTAssertEqual(repository.recordedCoordinates, [coordinate])
        XCTAssertEqual(repository.recordedRadii, [SpotMapViewModel.defaultRadiusKilometers])
        XCTAssertEqual(location.permissionRequestCount, 1)
        XCTAssertEqual(location.locationRequestCount, 1)
    }

    func testShowNearbyPermissionDeniedPublishesNoticeAndKeepsSpots() async {
        let repository = SpotRepositoryFake()
        let location = MapLocationProviderDouble(granted: false, coordinate: nil)
        let viewModel = makeViewModel(repository: repository, location: location)

        await viewModel.showNearby()

        XCTAssertEqual(viewModel.nearbyNotice, .permissionDenied)
        XCTAssertTrue(viewModel.spots.isEmpty)
        XCTAssertTrue(repository.recordedCoordinates.isEmpty, "Sin permiso no debe consultarse el repositorio")
        XCTAssertEqual(location.permissionRequestCount, 1)
        XCTAssertEqual(location.locationRequestCount, 0)
    }

    func testShowNearbyWithoutLocationPublishesNoLocationNotice() async {
        let repository = SpotRepositoryFake()
        let location = MapLocationProviderDouble(granted: true, coordinate: nil)
        let viewModel = makeViewModel(repository: repository, location: location)

        await viewModel.showNearby()

        XCTAssertEqual(viewModel.nearbyNotice, .noLocation)
        XCTAssertTrue(repository.recordedCoordinates.isEmpty)
        XCTAssertEqual(location.permissionRequestCount, 1)
        XCTAssertEqual(location.locationRequestCount, 1)
    }

    func testShowNearbyNoSpotsInRadiusPublishesNotice() async {
        let repository = SpotRepositoryFake()
        repository.nearbyResult = []
        let location = MapLocationProviderDouble(granted: true, coordinate: coordinate)
        let viewModel = makeViewModel(repository: repository, location: location)

        await viewModel.showNearby()

        XCTAssertEqual(viewModel.nearbyNotice, .noSpotsInRadius)
        XCTAssertTrue(viewModel.spots.isEmpty)
        XCTAssertEqual(repository.recordedCoordinates, [coordinate])
        XCTAssertEqual(repository.recordedRadii, [SpotMapViewModel.defaultRadiusKilometers])
    }

    func testShowNearbyRepositoryErrorPublishesLoadFailedNotice() async {
        let repository = SpotRepositoryFake()
        repository.nearbyResult = [makeSpot(name: "Cercano", distanceMeters: 100)]
        repository.nearbySpotsError = .queryFailed("red caída")
        let location = MapLocationProviderDouble(granted: true, coordinate: coordinate)
        let viewModel = makeViewModel(repository: repository, location: location)

        await viewModel.showNearby()

        XCTAssertEqual(viewModel.nearbyNotice, .loadFailed)
        XCTAssertTrue(viewModel.spots.isEmpty)
        XCTAssertEqual(repository.recordedCoordinates, [coordinate])
    }

    func testSelectPublishesSpotForNavigationAndClearSelectionResets() {
        let spot = makeSpot()
        let viewModel = makeViewModel(
            repository: SpotRepositoryFake(),
            location: MapLocationProviderDouble(granted: false, coordinate: nil)
        )

        viewModel.select(spot)

        XCTAssertEqual(viewModel.selectedSpot, spot)

        viewModel.clearSelection()

        XCTAssertNil(viewModel.selectedSpot)
    }

    func testLoadSpotsWithActiveSessionHighlightsFavoriteSpots() async {
        let repository = SpotRepositoryFake()
        let region = makeRegion()
        let favoriteSpot = makeSpot(name: "Favorito")
        repository.seed([favoriteSpot, makeSpot(name: "Normal")], for: region)
        repository.favoriteIDs = [favoriteSpot.id]
        let auth = SupabaseBaseFake()
        auth.isSessionActive = true
        let viewModel = makeViewModel(
            repository: repository,
            location: MapLocationProviderDouble(granted: false, coordinate: nil),
            auth: auth,
            region: region
        )

        await viewModel.loadSpots()

        XCTAssertEqual(viewModel.favoriteSpotIDs, [favoriteSpot.id])
        XCTAssertTrue(viewModel.isFavorite(favoriteSpot))
    }

    func testIsFavoriteFalseForSpotNotInFavoriteSet() async {
        let repository = SpotRepositoryFake()
        let region = makeRegion()
        let spot = makeSpot(name: "Sin favorito")
        repository.seed([spot], for: region)
        let auth = SupabaseBaseFake()
        auth.isSessionActive = true
        let viewModel = makeViewModel(
            repository: repository,
            location: MapLocationProviderDouble(granted: false, coordinate: nil),
            auth: auth,
            region: region
        )

        await viewModel.loadSpots()

        XCTAssertFalse(viewModel.isFavorite(spot))
    }

    func testSignedOutStateChangeClearsFavoriteSpotIDs() async {
        let repository = SpotRepositoryFake()
        let region = makeRegion()
        let favoriteSpot = makeSpot(name: "Favorito")
        repository.seed([favoriteSpot], for: region)
        repository.favoriteIDs = [favoriteSpot.id]
        let auth = SupabaseBaseFake()
        auth.isSessionActive = true
        auth.stateChangesEvents = [.signedOut]
        let viewModel = makeViewModel(
            repository: repository,
            location: MapLocationProviderDouble(granted: false, coordinate: nil),
            auth: auth,
            region: region
        )

        await viewModel.loadSpots()
        XCTAssertEqual(viewModel.favoriteSpotIDs, [favoriteSpot.id], "Antes del evento, la sesión activa carga los favoritos")

        if let task = viewModel.stateChangesTask {
            await task.value
        }

        XCTAssertTrue(viewModel.favoriteSpotIDs.isEmpty, "El cierre de sesión vacía el conjunto de favoritos")
    }

    func testFavoriteSpotIDsFailureLeavesMapLoadedWithoutFavorites() async {
        let repository = SpotRepositoryFake()
        let region = makeRegion()
        repository.seed([makeSpot(name: "A")], for: region)
        repository.favoriteSpotIDsError = .queryFailed("red caída")
        let auth = SupabaseBaseFake()
        auth.isSessionActive = true
        let viewModel = makeViewModel(
            repository: repository,
            location: MapLocationProviderDouble(granted: false, coordinate: nil),
            auth: auth,
            region: region
        )

        await viewModel.loadSpots()

        XCTAssertEqual(viewModel.state, .loaded, "El fallo de favoritos no debe romper el estado del mapa")
        XCTAssertEqual(viewModel.spots.map(\.name), ["A"], "El fallo de favoritos no debe tocar los spots cargados")
        XCTAssertTrue(viewModel.favoriteSpotIDs.isEmpty)
    }
}