import XCTest

@testable import BetterFishing

@MainActor
private final class FlowTestLocationProvider: DeviceLocationProviding {
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
final class SpotDiscoveryFlowIntegrationTests: XCTestCase {
    private static let sauID = "11111111-1111-1111-1111-111111111111"
    private static let barcelonetaID = "22222222-2222-2222-2222-222222222222"

    private static let sauSpotJSON = """
    {"id": "\(sauID)", "name": "Embalse de Sau", "category": "lake", "summary": "Amplia lámina de agua.", "longitude": 2.2486, "latitude": 42.0037}
    """

    private static let barcelonetaSpotJSON = """
    {"id": "\(barcelonetaID)", "name": "Barceloneta", "category": "shore", "summary": "Playa urbana junto al puerto.", "longitude": 2.1891, "latitude": 41.3754}
    """

    private static let nearbyRowsJSON = """
    [
      {"id": "\(barcelonetaID)", "name": "Barceloneta", "category": "shore", "summary": "Playa urbana junto al puerto.", "longitude": 2.1891, "latitude": 41.3754, "distance_m": 2500.0},
      {"id": "\(sauID)", "name": "Embalse de Sau", "category": "lake", "summary": "Amplia lámina de agua.", "longitude": 2.2486, "latitude": 42.0037, "distance_m": 67000.0}
    ]
    """

    private static let favoritesWithoutBarcelonetaJSON = """
    [{"spot_id": "\(sauID)"}]
    """

    private static let favoritesIncludingBarcelonetaJSON = """
    [
      {"spot_id": "\(sauID)"},
      {"spot_id": "\(barcelonetaID)"}
    ]
    """

    private static var barceloneta: Spot {
        Spot(
            id: UUID(uuidString: barcelonetaID)!,
            name: "Barceloneta",
            category: .shore,
            summary: "Playa urbana junto al puerto.",
            longitude: 2.1891,
            latitude: 41.3754,
            distanceMeters: nil
        )
    }

    private static func spotRPCFunctions(_ recorded: [BaseFakeRecordedRPC]) -> [String] {
        recorded.map(\.function).filter { $0 != "my_favorite_spots" }
    }

    func testFullDiscoveryAndFavoritesFlowWithStackOverBaseFake() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRows = [Self.sauSpotJSON, Self.barcelonetaSpotJSON]
        let stack = SupabaseStack(auth: fake, storage: fake, database: fake)
        let services = AppComposition.makeRootServices(arguments: [], supabaseStack: stack)

        let repository = try XCTUnwrap(services.spotRepository, "Con stack el repositorio de spots debe inyectarse (Req 2.1)")
        XCTAssertNotNil(repository)
        XCTAssertNotNil(services.spotMapViewModel, "Con stack el ViewModel del mapa de la composición debe construirse")
        XCTAssertEqual(services.spotMapViewModel?.state, .loading)
        XCTAssertNotNil(services.spotDetailViewModelFactory, "Con stack la factory de detalle debe construirse")

        let location = FlowTestLocationProvider(
            granted: true,
            coordinate: LocationCoordinate2D(latitude: 41.4, longitude: 2.2)
        )
        let mapViewModel = SpotMapViewModel(repository: repository, locationProvider: location)

        await mapViewModel.loadSpots()

        XCTAssertEqual(mapViewModel.state, .loaded, "La carga de la región debe dejar el mapa en loaded (Req 1.1)")
        XCTAssertEqual(mapViewModel.spots.map(\.name), ["Embalse de Sau", "Barceloneta"], "El select de la región devuelve los spots sembrados")
        XCTAssertEqual(fake.recordedSelects.filter { $0.table == "spots" }.count, 1, "El mapa debe consultar una única vez la región (Req 1.1)")
        XCTAssertEqual(fake.recordedSelects.first(where: { $0.table == "spots" })?.table, "spots")
        XCTAssertEqual(fake.recordedSelects.first(where: { $0.table == "spots" })?.columns, "id,name,category,summary,longitude,latitude")

        fake.cannedRPCValue = Self.nearbyRowsJSON
        await mapViewModel.showNearby()

        XCTAssertEqual(mapViewModel.state, .loaded)
        XCTAssertEqual(mapViewModel.spots.map(\.distanceMeters), [2500.0, 67000.0], "Cerca de mí ordena por distancia creciente (Req 3.1)")
        XCTAssertEqual(mapViewModel.spots.first?.name, "Barceloneta")
        XCTAssertNil(mapViewModel.nearbyNotice)
        XCTAssertEqual(Self.spotRPCFunctions(fake.recordedRPCs), ["nearby_spots"], "Cerca de mí ejecuta la RPC nearby_spots (Req 3.1)")
        XCTAssertEqual(fake.recordedRPCs.first?.arguments?.values["lat"], .double(41.4))
        XCTAssertEqual(fake.recordedRPCs.first?.arguments?.values["lng"], .double(2.2))
        XCTAssertEqual(
            fake.recordedRPCs.first?.arguments?.values["radius_km"],
            .double(SpotMapViewModel.defaultRadiusKilometers)
        )

        mapViewModel.select(Self.barceloneta)
        let selected = try XCTUnwrap(mapViewModel.selectedSpot, "Seleccionar una anotación publica el spot (Req 4.1)")
        let factory = try XCTUnwrap(services.spotDetailViewModelFactory)
        let detailViewModel = factory(selected)
        XCTAssertEqual(detailViewModel.spot, Self.barceloneta, "El detalle se construye con el spot seleccionado (Req 4.1)")

        fake.cannedRPCValue = Self.favoritesWithoutBarcelonetaJSON
        await detailViewModel.load()

        XCTAssertEqual(Self.spotRPCFunctions(fake.recordedRPCs), ["nearby_spots", "my_favorite_spot_ids"])
        XCTAssertFalse(detailViewModel.isFavorite, "El spot no está entre los favoritos de la cuenta al cargar (Req 5.3)")
        XCTAssertFalse(detailViewModel.isLoading)

        await detailViewModel.toggleFavorite()

        XCTAssertTrue(detailViewModel.isFavorite, "Con sesión el toggle marca el favorito (Req 5.1)")
        XCTAssertNil(detailViewModel.toggleErrorMessage)
        XCTAssertFalse(detailViewModel.sessionRequiredNotice)
        let addRecorded = try XCTUnwrap(fake.recordedRPCs.last)
        XCTAssertEqual(addRecorded.function, "add_spot_favorite")
        XCTAssertEqual(
            addRecorded.arguments?.values,
            ["spot_id": .string(Self.barcelonetaID)],
            "El favorito se guarda con la RPC add_spot_favorite y el spot_id (Req 5.1)"
        )

        fake.isSessionActive = false
        fake.stateChangesEvents = [.signedOut]
        await detailViewModel.load()
        await detailViewModel.stateChangesTask?.value

        XCTAssertFalse(detailViewModel.isFavorite, "El cierre de sesión desmarca el favorito (Req 5.5)")
        XCTAssertTrue(detailViewModel.sessionRequiredNotice, "Sin sesión el toggle muestra el aviso de iniciar sesión (Req 5.4)")

        await detailViewModel.toggleFavorite()
        XCTAssertTrue(detailViewModel.sessionRequiredNotice)
        XCTAssertFalse(detailViewModel.isFavorite)
        XCTAssertEqual(
            fake.recordedRPCs.filter { $0.function == "add_spot_favorite" || $0.function == "remove_spot_favorite" }.count,
            1,
            "Sin sesión el toggle no debe llamar a ninguna RPC de favorito (Req 5.4)"
        )

        fake.isSessionActive = true
        fake.cannedRPCValue = Self.favoritesIncludingBarcelonetaJSON
        fake.stateChangesEvents = [.signedIn(SupabaseBaseFake.defaultSession)]
        await detailViewModel.load()
        await detailViewModel.stateChangesTask?.value

        XCTAssertTrue(detailViewModel.isFavorite, "El inicio de sesión refresca el estado según la cuenta activa (Req 5.5)")
        XCTAssertFalse(detailViewModel.sessionRequiredNotice)
        XCTAssertEqual(
            fake.recordedRPCs.filter { $0.function == "my_favorite_spot_ids" }.count,
            3,
            "La recarga de sesión re-consulta los favoritos en load() y en el evento signedIn (Req 5.5)"
        )

        await detailViewModel.toggleFavorite()

        XCTAssertFalse(detailViewModel.isFavorite, "Con sesión el toggle desmarca el favorito (Req 5.2)")
        let removeRecorded = try XCTUnwrap(fake.recordedRPCs.last)
        XCTAssertEqual(removeRecorded.function, "remove_spot_favorite")
        XCTAssertEqual(
            removeRecorded.arguments?.values,
            ["spot_id": .string(Self.barcelonetaID)],
            "El favorito se elimina con la RPC remove_spot_favorite y el spot_id (Req 5.2)"
        )
    }

    func testFlowWithoutStackDegradesToUnavailableWithoutCrashing() async {
        let services = AppComposition.makeRootServices(arguments: [])

        XCTAssertNil(services.supabase, "Sin configuración el stack de Supabase queda en nil")
        XCTAssertNil(services.spotRepository, "Sin capa de datos el repositorio de spots debe ser nil (Req 2.1)")
        XCTAssertNil(services.spotMapViewModel, "Sin capa de datos el ViewModel del mapa debe ser nil (Req 2.1)")
        XCTAssertNil(services.spotDetailViewModelFactory, "Sin capa de datos la factory de detalle debe ser nil (Req 2.1)")
        XCTAssertNotNil(services.scannerViewModel, "El resto de la app sigue construyéndose")
        XCTAssertNotNil(services.catchSaver)
        XCTAssertNotNil(services.catchLogViewModel)

        let location = FlowTestLocationProvider(
            granted: true,
            coordinate: LocationCoordinate2D(latitude: 41.4, longitude: 2.2)
        )
        let mapViewModel = SpotMapViewModel(repository: nil, locationProvider: location)

        XCTAssertEqual(mapViewModel.state, .unavailable, "La pestaña Mapa queda en no disponible (Req 2.1)")

        await mapViewModel.loadSpots()
        XCTAssertEqual(mapViewModel.state, .unavailable, "La carga de la región no rompe sin capa de datos")
        XCTAssertTrue(mapViewModel.spots.isEmpty)

        await mapViewModel.showNearby()
        XCTAssertEqual(mapViewModel.state, .unavailable, "Cerca de mí no rompe sin capa de datos (Req 2.1)")
        XCTAssertNil(mapViewModel.nearbyNotice)
        XCTAssertEqual(location.permissionRequestCount, 0, "Sin repositorio no debe pedirse permiso de ubicación")
        XCTAssertEqual(location.locationRequestCount, 0)
    }
}