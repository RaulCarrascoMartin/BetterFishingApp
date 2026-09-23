import Foundation
import XCTest

@testable import BetterFishing

final class SpotRepositoryFakeTests: XCTestCase {
    private let firstID = UUID()
    private let secondID = UUID()

    private func makeCoordinate(latitude: Double, longitude: Double) -> LocationCoordinate2D {
        LocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func makeSpot(
        id: UUID,
        name: String,
        category: SpotCategory = .lake,
        latitude: Double,
        longitude: Double,
        distanceMeters: Double? = nil
    ) -> Spot {
        Spot(
            id: id,
            name: name,
            category: category,
            summary: "Resumen de prueba",
            longitude: longitude,
            latitude: latitude,
            distanceMeters: distanceMeters
        )
    }

    private func makeRegion(centerLatitude: Double = 41.0, centerLongitude: Double = 2.0) -> SpotRegion {
        SpotRegion(
            center: makeCoordinate(latitude: centerLatitude, longitude: centerLongitude),
            latitudinalMeters: 111_320.0,
            longitudinalMeters: 111_320.0 * cos(centerLatitude * .pi / 180)
        )
    }

    private func makeMountainRegion(centerLatitude: Double = 42.0, centerLongitude: Double = 1.0) -> SpotRegion {
        SpotRegion(
            center: makeCoordinate(latitude: centerLatitude, longitude: centerLongitude),
            latitudinalMeters: 111_320.0,
            longitudinalMeters: 111_320.0 * cos(centerLatitude * .pi / 180)
        )
    }

    func testFakeConformsAsAnySpotRepository() async throws {
        let region = makeRegion()
        let spot = makeSpot(id: firstID, name: "Embalse de Sau", latitude: 42.0, longitude: 2.2)
        let fake = SpotRepositoryFake()
        fake.seed([spot], for: region)
        fake.favoriteIDs = [firstID]
        fake.nearbyResult = [spot]

        let repository: any SpotRepository = fake

        let listed = try await repository.listSpots(region: region)
        XCTAssertEqual(listed, [spot])

        let nearby = try await repository.nearbySpots(
            from: makeCoordinate(latitude: 41.0, longitude: 2.0),
            radiusKilometers: 50
        )
        XCTAssertEqual(nearby, [spot])

        let found = try await repository.spot(id: firstID)
        XCTAssertEqual(found, spot)

        let ids = try await repository.favoriteSpotIDs()
        XCTAssertEqual(ids, [firstID])

        let favorites = try await repository.favoriteSpots()
        XCTAssertEqual(favorites, [spot])

        try await repository.setFavorite(spotID: firstID, isFavorite: false)
        let idsAfterToggle = try await repository.favoriteSpotIDs()
        XCTAssertTrue(idsAfterToggle.isEmpty)
    }

    func testListSpotsReturnsSeededSpotsPerRegionAndRecordsRegions() async throws {
        let coastRegion = makeRegion()
        let mountainRegion = makeMountainRegion()
        let coastSpot = makeSpot(id: firstID, name: "Port de Barcelona", category: .sea, latitude: 41.37, longitude: 2.18)
        let mountainSpot = makeSpot(id: secondID, name: "Embalse de Sau", latitude: 42.00, longitude: 2.24)
        let fake = SpotRepositoryFake()
        fake.seed([coastSpot], for: coastRegion)
        fake.seed([mountainSpot], for: mountainRegion)

        let coast = try await fake.listSpots(region: coastRegion)
        let mountains = try await fake.listSpots(region: mountainRegion)

        XCTAssertEqual(coast, [coastSpot])
        XCTAssertEqual(mountains, [mountainSpot])
        XCTAssertEqual(fake.recordedRegions, [coastRegion, mountainRegion])
    }

    func testListSpotsReturnsEmptyForUnseededRegionAndStillRecords() async throws {
        let fake = SpotRepositoryFake()
        let region = makeRegion()

        let spots = try await fake.listSpots(region: region)

        XCTAssertTrue(spots.isEmpty)
        XCTAssertEqual(fake.recordedRegions, [region])
    }

    func testNearbySpotsSortsByDistanceAscendingNilLastAndRecordsCoordinateAndRadius() async throws {
        let far = makeSpot(id: firstID, name: "Costa Brava", latitude: 42.0, longitude: 3.0, distanceMeters: 5_000)
        let near = makeSpot(id: secondID, name: "Marina Vela", latitude: 41.37, longitude: 2.18, distanceMeters: 120)
        let withoutDistance = makeSpot(id: UUID(), name: "Delta del Ebro", latitude: 40.7, longitude: 0.8, distanceMeters: nil)
        let fake = SpotRepositoryFake()
        fake.nearbyResult = [far, withoutDistance, near]
        let coordinate = makeCoordinate(latitude: 41.38, longitude: 2.19)

        let spots = try await fake.nearbySpots(from: coordinate, radiusKilometers: 25)

        XCTAssertEqual(spots.map(\.id), [secondID, firstID, withoutDistance.id])
        XCTAssertEqual(spots.first?.distanceMeters, 120)
        XCTAssertNil(spots.last?.distanceMeters)
        XCTAssertEqual(fake.recordedCoordinates, [coordinate])
        XCTAssertEqual(fake.recordedRadii, [25])
    }

    func testSpotReturnsMatchingSeededSpotAndRecordsID() async throws {
        let coastRegion = makeRegion()
        let mountainRegion = makeMountainRegion()
        let coastSpot = makeSpot(id: firstID, name: "Port de Barcelona", category: .sea, latitude: 41.37, longitude: 2.18)
        let mountainSpot = makeSpot(id: secondID, name: "Embalse de Sau", latitude: 42.00, longitude: 2.24)
        let fake = SpotRepositoryFake()
        fake.seed([coastSpot], for: coastRegion)
        fake.seed([mountainSpot], for: mountainRegion)

        let missingID = UUID()
        let found = try await fake.spot(id: secondID)
        let missing = try await fake.spot(id: missingID)

        XCTAssertEqual(found, mountainSpot)
        XCTAssertNil(missing)
        XCTAssertEqual(fake.recordedSpotIDs, [secondID, missingID])
    }

    func testFavoriteSpotIDsReturnsProgrammedSet() async throws {
        let fake = SpotRepositoryFake()
        fake.favoriteIDs = [firstID, secondID]

        let ids = try await fake.favoriteSpotIDs()

        XCTAssertEqual(ids, Set([firstID, secondID]))
    }

    func testFavoriteSpotsReturnsSeededSpotsMatchingFavoriteIDsInSeedOrder() async throws {
        let region = makeRegion()
        let first = makeSpot(id: firstID, name: "Embalse de Sau", latitude: 42.0, longitude: 2.2)
        let second = makeSpot(id: secondID, name: "Port de Barcelona", category: .sea, latitude: 41.37, longitude: 2.18)
        let third = makeSpot(id: UUID(), name: "Delta del Ebro", latitude: 40.7, longitude: 0.8)
        let fake = SpotRepositoryFake()
        fake.seed([first, second, third], for: region)
        fake.favoriteIDs = [secondID, firstID]

        let favorites = try await fake.favoriteSpots()

        XCTAssertEqual(favorites, [first, second])
    }

    func testSetFavoriteAddsAndRemovesIDsAndRecordsToggles() async throws {
        let fake = SpotRepositoryFake()

        try await fake.setFavorite(spotID: firstID, isFavorite: true)
        XCTAssertEqual(fake.favoriteIDs, [firstID])

        try await fake.setFavorite(spotID: firstID, isFavorite: false)
        XCTAssertTrue(fake.favoriteIDs.isEmpty)

        XCTAssertEqual(
            fake.recordedFavoriteToggles,
            [
                SpotRepositoryFake.RecordedFavoriteToggle(spotID: firstID, isFavorite: true),
                SpotRepositoryFake.RecordedFavoriteToggle(spotID: firstID, isFavorite: false)
            ]
        )
        XCTAssertEqual(fake.recordedSpotIDs, [firstID, firstID])
    }

    func testListSpotsForcedErrorThrowsAndRecordsButOtherSeamsWork() async throws {
        let fake = SpotRepositoryFake()
        fake.listSpotsError = .queryFailed("región sin datos")
        fake.nearbyResult = [makeSpot(id: firstID, name: "Marina Vela", latitude: 41.37, longitude: 2.18, distanceMeters: 500)]
        let region = makeRegion()

        do {
            _ = try await fake.listSpots(region: region)
            XCTFail("Se esperaba que listSpots lanzara el error programado")
        } catch let error as SpotRepositoryError {
            XCTAssertEqual(error, .queryFailed("región sin datos"))
        }

        XCTAssertEqual(fake.recordedRegions, [region])

        let nearby = try await fake.nearbySpots(
            from: makeCoordinate(latitude: 41.0, longitude: 2.0),
            radiusKilometers: 10
        )
        XCTAssertEqual(nearby.count, 1)
    }

    func testNearbySpotsForcedErrorThrowsAndStillRecordsCoordinateAndRadius() async throws {
        let fake = SpotRepositoryFake()
        fake.nearbySpotsError = .backendUnavailable
        let coordinate = makeCoordinate(latitude: 41.38, longitude: 2.19)

        do {
            _ = try await fake.nearbySpots(from: coordinate, radiusKilometers: 30)
            XCTFail("Se esperaba que nearbySpots lanzara el error programado")
        } catch let error as SpotRepositoryError {
            XCTAssertEqual(error, .backendUnavailable)
        }

        XCTAssertEqual(fake.recordedCoordinates, [coordinate])
        XCTAssertEqual(fake.recordedRadii, [30])
    }

    func testSpotForcedErrorThrowsAndRecordsID() async throws {
        let fake = SpotRepositoryFake()
        fake.spotError = .authenticationRequired

        do {
            _ = try await fake.spot(id: firstID)
            XCTFail("Se esperaba que spot(id:) lanzara el error programado")
        } catch let error as SpotRepositoryError {
            XCTAssertEqual(error, .authenticationRequired)
        }

        XCTAssertEqual(fake.recordedSpotIDs, [firstID])
    }

    func testFavoriteSpotIDsForcedErrorThrows() async throws {
        let fake = SpotRepositoryFake()
        fake.favoriteSpotIDsError = .backendUnavailable

        do {
            _ = try await fake.favoriteSpotIDs()
            XCTFail("Se esperaba que favoriteSpotIDs lanzara el error programado")
        } catch let error as SpotRepositoryError {
            XCTAssertEqual(error, .backendUnavailable)
        }
    }

    func testFavoriteSpotsForcedErrorThrows() async throws {
        let fake = SpotRepositoryFake()
        fake.favoriteSpotsError = .queryFailed("favoritos sin soporte")

        do {
            _ = try await fake.favoriteSpots()
            XCTFail("Se esperaba que favoriteSpots lanzara el error programado")
        } catch let error as SpotRepositoryError {
            XCTAssertEqual(error, .queryFailed("favoritos sin soporte"))
        }
    }

    func testSetFavoriteForcedErrorThrowsRecordsToggleAndKeepsFavoriteStateUnchanged() async throws {
        let fake = SpotRepositoryFake()
        fake.favoriteIDs = [secondID]
        fake.setFavoriteError = .authenticationRequired

        do {
            try await fake.setFavorite(spotID: firstID, isFavorite: true)
            XCTFail("Se esperaba que setFavorite lanzara el error programado")
        } catch let error as SpotRepositoryError {
            XCTAssertEqual(error, .authenticationRequired)
        }

        XCTAssertEqual(
            fake.recordedFavoriteToggles,
            [SpotRepositoryFake.RecordedFavoriteToggle(spotID: firstID, isFavorite: true)]
        )
        XCTAssertEqual(fake.recordedSpotIDs, [firstID])
        XCTAssertEqual(fake.favoriteIDs, [secondID])
    }

    func testPerSeamErrorsAreIsolated() async throws {
        let fake = SpotRepositoryFake()
        fake.setFavoriteError = .authenticationRequired
        let region = makeRegion()
        let spot = makeSpot(id: firstID, name: "Embalse de Sau", latitude: 42.0, longitude: 2.2)
        fake.seed([spot], for: region)
        fake.favoriteIDs = [firstID]

        do {
            _ = try await fake.setFavorite(spotID: secondID, isFavorite: true)
            XCTFail("Se esperaba el error programado en setFavorite")
        } catch {
        }

        let listed = try await fake.listSpots(region: region)
        XCTAssertEqual(listed, [spot])
        let ids = try await fake.favoriteSpotIDs()
        XCTAssertEqual(ids, [firstID])
    }

    func testResetClearsRecordingsButKeepsProgrammedState() async throws {
        let region = makeRegion()
        let spot = makeSpot(id: firstID, name: "Embalse de Sau", latitude: 42.0, longitude: 2.2)
        let fake = SpotRepositoryFake()
        fake.seed([spot], for: region)
        fake.favoriteIDs = [firstID]

        _ = try await fake.listSpots(region: region)
        _ = try await fake.spot(id: firstID)
        try await fake.setFavorite(spotID: secondID, isFavorite: true)

        fake.reset()

        XCTAssertTrue(fake.recordedRegions.isEmpty)
        XCTAssertTrue(fake.recordedCoordinates.isEmpty)
        XCTAssertTrue(fake.recordedRadii.isEmpty)
        XCTAssertTrue(fake.recordedSpotIDs.isEmpty)
        XCTAssertTrue(fake.recordedFavoriteToggles.isEmpty)

        let listedAfterReset = try await fake.listSpots(region: region)
        XCTAssertEqual(listedAfterReset, [spot])
        XCTAssertEqual(fake.favoriteIDs, [firstID, secondID])
        XCTAssertEqual(fake.recordedRegions.count, 1)
    }
}