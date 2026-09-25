import Foundation
import XCTest

@testable import BetterFishing

final class SupabaseSpotRepositoryTests: XCTestCase {
    private static let spotID = "11111111-1111-1111-1111-111111111111"
    private static let secondSpotID = "22222222-2222-2222-2222-222222222222"

    private static let bareSpotJSON = """
    {"id": "11111111-1111-1111-1111-111111111111", "name": "Embalse de Sau", "category": "lake", "summary": "Amplia lámina de agua.", "longitude": 2.2486, "latitude": 42.0037}
    """

    private static let secondSpotJSON = """
    {"id": "22222222-2222-2222-2222-222222222222", "name": "Port de Barcelona", "category": "sea", "summary": "Marina y dique del puerto.", "longitude": 2.1896, "latitude": 41.3744}
    """

    private static let nearbyRowsJSON = """
    [
      {"id": "11111111-1111-1111-1111-111111111111", "name": "Port de Barcelona", "category": "sea", "summary": "Marina y dique del puerto.", "longitude": 2.1896, "latitude": 41.3744, "distance_m": 2530.7},
      {"id": "22222222-2222-2222-2222-222222222222", "name": "Embalse de Sau", "category": "lake", "summary": "Amplia lámina de agua.", "longitude": 2.2486, "latitude": 42.0037, "distance_m": 67000.0}
    ]
    """

    private static let favoriteIDsJSON = """
    [{"spot_id": "11111111-1111-1111-1111-111111111111"}, {"spot_id": "22222222-2222-2222-2222-222222222222"}]
    """

    private func makeRepository(fake: SupabaseBaseFake) -> SupabaseSpotRepository {
        SupabaseSpotRepository(database: fake, auth: fake)
    }

    private func makeRegion() -> SpotRegion {
        SpotRegion(
            center: LocationCoordinate2D(latitude: 41.0, longitude: 2.0),
            latitudinalMeters: 111_320.0,
            longitudinalMeters: 111_320.0 * cos(41.0 * .pi / 180)
        )
    }

    func testListSpotsDecodesSpotsAndSelectsRegionBox() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRows = [Self.bareSpotJSON, Self.secondSpotJSON]
        let repository = makeRepository(fake: fake)
        let region = makeRegion()

        let spots = try await repository.listSpots(region: region)

        XCTAssertEqual(spots.count, 2)
        XCTAssertNil(spots[0].distanceMeters)
        XCTAssertNil(spots[1].distanceMeters)
        XCTAssertEqual(spots[0].category, .lake)
        XCTAssertEqual(spots[1].name, "Port de Barcelona")

        let recorded = try XCTUnwrap(fake.recordedSelects.first)
        XCTAssertEqual(fake.recordedSelects.count, 1)
        XCTAssertEqual(recorded.table, "spots")
        XCTAssertEqual(recorded.columns, "id,name,category,summary,longitude,latitude")
        XCTAssertNil(recorded.limit)
        XCTAssertEqual(recorded.filters.count, 4)
        XCTAssertTrue(recorded.filters.contains(
            SupabaseFilter(column: "longitude", operator: .gte, value: String(region.minLongitude))
        ))
        XCTAssertTrue(recorded.filters.contains(
            SupabaseFilter(column: "longitude", operator: .lte, value: String(region.maxLongitude))
        ))
        XCTAssertTrue(recorded.filters.contains(
            SupabaseFilter(column: "latitude", operator: .gte, value: String(region.minLatitude))
        ))
        XCTAssertTrue(recorded.filters.contains(
            SupabaseFilter(column: "latitude", operator: .lte, value: String(region.maxLatitude))
        ))
        XCTAssertTrue(fake.recordedRPCs.isEmpty)
    }

    func testNearbySpotsCallsRPCWithLatLngRadiusAndFillsDistanceMeters() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRPCValue = Self.nearbyRowsJSON
        let repository = makeRepository(fake: fake)
        let coordinate = LocationCoordinate2D(latitude: 41.3744, longitude: 2.1896)

        let spots = try await repository.nearbySpots(from: coordinate, radiusKilometers: 50)

        XCTAssertEqual(spots.count, 2)
        XCTAssertEqual(spots[0].name, "Port de Barcelona")
        XCTAssertEqual(spots[0].distanceMeters, 2530.7)
        XCTAssertEqual(spots[1].distanceMeters, 67_000.0)

        let recorded = try XCTUnwrap(fake.recordedRPCs.first)
        XCTAssertEqual(fake.recordedRPCs.count, 1)
        XCTAssertEqual(recorded.function, "nearby_spots")
        XCTAssertEqual(recorded.arguments?.values["lat"], .double(41.3744))
        XCTAssertEqual(recorded.arguments?.values["lng"], .double(2.1896))
        XCTAssertEqual(recorded.arguments?.values["radius_km"], .double(50))
        XCTAssertEqual(recorded.arguments?.values.count, 3)
        XCTAssertTrue(fake.recordedSelects.isEmpty)
    }

    func testSpotByIDReturnsDecodedSpotWithEqFilterAndLimit() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRows = [Self.bareSpotJSON]
        let repository = makeRepository(fake: fake)
        let id = try XCTUnwrap(UUID(uuidString: Self.spotID))

        let spot = try await repository.spot(id: id)

        XCTAssertEqual(spot?.id, id)
        XCTAssertEqual(spot?.name, "Embalse de Sau")
        XCTAssertNil(spot?.distanceMeters)

        let recorded = try XCTUnwrap(fake.recordedSelects.first)
        XCTAssertEqual(recorded.table, "spots")
        XCTAssertEqual(recorded.limit, 1)
        XCTAssertEqual(recorded.filters, [SupabaseFilter(column: "id", operator: .eq, value: id.uuidString)])
    }

    func testSpotByIDReturnsNilWhenNoRowsMatch() async throws {
        let fake = SupabaseBaseFake()
        let repository = makeRepository(fake: fake)

        let spot = try await repository.spot(id: UUID())

        XCTAssertNil(spot)
    }

    func testFavoriteSpotIDsReturnsSetFromRPC() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRPCValue = Self.favoriteIDsJSON
        let repository = makeRepository(fake: fake)

        let ids = try await repository.favoriteSpotIDs()

        let expected = try XCTUnwrap(UUID(uuidString: Self.spotID))
        let expectedSecond = try XCTUnwrap(UUID(uuidString: Self.secondSpotID))
        XCTAssertEqual(ids, Set([expected, expectedSecond]))

        let recorded = try XCTUnwrap(fake.recordedRPCs.first)
        XCTAssertEqual(fake.recordedRPCs.count, 1)
        XCTAssertEqual(recorded.function, "my_favorite_spot_ids")
        XCTAssertNil(recorded.arguments)
    }

    func testFavoriteSpotIDsWithoutSessionReturnsEmptySetWithoutRPC() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        fake.cannedRPCValue = Self.favoriteIDsJSON
        let repository = makeRepository(fake: fake)

        let ids = try await repository.favoriteSpotIDs()

        XCTAssertTrue(ids.isEmpty)
        XCTAssertTrue(fake.recordedRPCs.isEmpty)
    }

    func testFavoriteSpotsDecodesSpotsFromRPC() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRPCValue = "[\(Self.bareSpotJSON), \(Self.secondSpotJSON)]"
        let repository = makeRepository(fake: fake)

        let spots = try await repository.favoriteSpots()

        XCTAssertEqual(spots.count, 2)
        XCTAssertNil(spots[0].distanceMeters)
        XCTAssertEqual(spots[1].category, .sea)

        let recorded = try XCTUnwrap(fake.recordedRPCs.first)
        XCTAssertEqual(recorded.function, "my_favorite_spots")
    }

    func testSetFavoriteWithoutSessionThrowsAuthenticationRequired() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        let repository = makeRepository(fake: fake)
        let spotID = try XCTUnwrap(UUID(uuidString: Self.spotID))

        do {
            try await repository.setFavorite(spotID: spotID, isFavorite: true)
            XCTFail("Se esperaba SpotRepositoryError.authenticationRequired")
        } catch let error as SpotRepositoryError {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
        XCTAssertTrue(fake.recordedRPCs.isEmpty)
    }

    func testSetFavoriteWithSessionCallsAddFavoriteRPC() async throws {
        let fake = SupabaseBaseFake()
        let repository = makeRepository(fake: fake)
        let spotID = try XCTUnwrap(UUID(uuidString: Self.spotID))

        try await repository.setFavorite(spotID: spotID, isFavorite: true)

        let recorded = try XCTUnwrap(fake.recordedRPCs.first)
        XCTAssertEqual(fake.recordedRPCs.count, 1)
        XCTAssertEqual(recorded.function, "add_spot_favorite")
        XCTAssertEqual(recorded.arguments?.values, ["spot_id": .string(spotID.uuidString)])
    }

    func testRemoveFavoriteWithSessionCallsRemoveFavoriteRPC() async throws {
        let fake = SupabaseBaseFake()
        let repository = makeRepository(fake: fake)
        let spotID = try XCTUnwrap(UUID(uuidString: Self.spotID))

        try await repository.setFavorite(spotID: spotID, isFavorite: false)

        let recorded = try XCTUnwrap(fake.recordedRPCs.first)
        XCTAssertEqual(fake.recordedRPCs.count, 1)
        XCTAssertEqual(recorded.function, "remove_spot_favorite")
        XCTAssertEqual(recorded.arguments?.values, ["spot_id": .string(spotID.uuidString)])
    }

    func testDatabaseFailureOnFavoriteMutationTranslatesToQueryFailed() async throws {
        let fake = SupabaseBaseFake()
        fake.databaseError = SupabaseBaseError.rpcFailed
        let repository = makeRepository(fake: fake)
        let spotID = try XCTUnwrap(UUID(uuidString: Self.spotID))
        let rpcDescription = try XCTUnwrap(SupabaseBaseError.rpcFailed.errorDescription)

        do {
            try await repository.setFavorite(spotID: spotID, isFavorite: true)
            XCTFail("Se esperaba un error del repositorio")
        } catch let error as SpotRepositoryError {
            XCTAssertEqual(
                error,
                .queryFailed("add_spot_favorite: \(rpcDescription)")
            )
        } catch {
            XCTFail("Error inesperado: \(error)")
        }

        let recorded = try XCTUnwrap(fake.recordedRPCs.first)
        XCTAssertEqual(fake.recordedRPCs.count, 1)
        XCTAssertEqual(recorded.function, "add_spot_favorite")
        XCTAssertEqual(recorded.arguments?.values, ["spot_id": .string(spotID.uuidString)])
    }

    func testDatabaseFailureOnSelectTranslatesToQueryFailed() async throws {
        let fake = SupabaseBaseFake()
        fake.databaseError = SupabaseBaseFakeError(reason: "red caída")
        let repository = makeRepository(fake: fake)

        do {
            _ = try await repository.listSpots(region: makeRegion())
            XCTFail("Se esperaba un error del repositorio")
        } catch let error as SpotRepositoryError {
            guard case let .queryFailed(description) = error else {
                XCTFail("Se esperaba .queryFailed, recibido \(error)")
                return
            }
            XCTAssertTrue(description.contains("listSpots"))
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func testDatabaseFailureOnRPCTranslatesToQueryFailed() async throws {
        let fake = SupabaseBaseFake()
        fake.databaseError = SupabaseBaseFakeError(reason: "rpc caída")
        let repository = makeRepository(fake: fake)

        do {
            _ = try await repository.nearbySpots(
                from: LocationCoordinate2D(latitude: 41.0, longitude: 2.0),
                radiusKilometers: 10
            )
            XCTFail("Se esperaba un error del repositorio")
        } catch let error as SpotRepositoryError {
            guard case let .queryFailed(description) = error else {
                XCTFail("Se esperaba .queryFailed, recibido \(error)")
                return
            }
            XCTAssertTrue(description.contains("nearbySpots"))
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }
}