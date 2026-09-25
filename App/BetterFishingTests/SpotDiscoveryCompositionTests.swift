import XCTest
import Supabase

@testable import BetterFishing

@MainActor
final class SpotDiscoveryCompositionTests: XCTestCase {
    private static let spotID = "11111111-1111-1111-1111-111111111111"

    private static let spotJSON = """
    {"id": "11111111-1111-1111-1111-111111111111", "name": "Embalse de Sau", "category": "lake", "summary": "Amplia lámina de agua.", "longitude": 2.2486, "latitude": 42.0037}
    """

    private static var sampleSpot: Spot {
        Spot(
            id: UUID(uuidString: spotID)!,
            name: "Embalse de Sau",
            category: .lake,
            summary: "Amplia lámina de agua.",
            longitude: 2.2486,
            latitude: 42.0037,
            distanceMeters: nil
        )
    }

    func testMakeRootServicesWithoutStackKeepsSpotServicesNil() throws {
        let invalidURL = try XCTUnwrap(URL(string: "http://"))
        let configuration = SupabaseClientConfiguration(projectURL: invalidURL, anonKey: "test-anon-key")

        let services = AppComposition.makeRootServices(arguments: [], supabaseConfiguration: configuration)

        XCTAssertNil(services.supabase)
        XCTAssertNil(services.spotRepository, "Sin capa de datos el repositorio de spots debe ser nil (Req 2.1)")
        XCTAssertNil(services.spotMapViewModel, "Sin capa de datos el ViewModel del mapa debe ser nil (Req 2.1)")
        XCTAssertNil(services.spotDetailViewModelFactory, "Sin capa de datos la factory de detalle debe ser nil (Req 2.1)")
        XCTAssertNotNil(services.scannerViewModel)
        XCTAssertNotNil(services.catchSaver)
        XCTAssertNotNil(services.catchLogViewModel)
        XCTAssertNotNil(services.migrator)
    }

    func testMakeRootServicesWithStackOverBaseFakeBuildsSpotRepositoryAndFunctionalMap() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRows = [Self.spotJSON]
        let stack = SupabaseStack(auth: fake, storage: fake, database: fake)

        let services = AppComposition.makeRootServices(arguments: [], supabaseStack: stack)

        let repository = try XCTUnwrap(services.spotRepository, "Con stack el repositorio de spots debe inyectarse")
        XCTAssertNotNil(repository)

        let mapViewModel = try XCTUnwrap(services.spotMapViewModel, "Con stack el ViewModel del mapa debe construirse")
        XCTAssertEqual(mapViewModel.state, .loading, "Con repositorio el mapa arranca en carga")

        await mapViewModel.loadSpots()

        XCTAssertEqual(mapViewModel.state, .loaded, "La carga de la región debe dejar el mapa en loaded")
        XCTAssertEqual(mapViewModel.spots, [Self.sampleSpot], "El repositorio backend devuelve los spots sembrados")

        XCTAssertEqual(fake.recordedSelects.filter { $0.table == "spots" }.count, 1, "El mapa debe lanzar una única carga de la región (Req 1.1)")
        XCTAssertEqual(fake.recordedSelects.first(where: { $0.table == "spots" })?.table, "spots")

        let factory = try XCTUnwrap(services.spotDetailViewModelFactory, "Con stack la factory de detalle debe existir")
        let detailViewModel = factory(Self.sampleSpot)
        XCTAssertEqual(detailViewModel.spot, Self.sampleSpot, "La factory construye el detalle del spot seleccionado")
    }
}