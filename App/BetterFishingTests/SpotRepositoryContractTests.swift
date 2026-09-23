import Foundation
import XCTest

@testable import BetterFishing

/// Doble mínimo de `SpotRepository` (solo Foundation, sin Supabase) para verificar el contrato.
private struct SpotsRepositoryTestDouble: SpotRepository {
    let listResult: [Spot]
    let nearbyResult: [Spot]
    let spotResult: Spot?
    let favoriteIDsResult: Set<UUID>
    let favoriteSpotsResult: [Spot]

    func listSpots(region: SpotRegion) async throws -> [Spot] {
        listResult
    }

    func nearbySpots(from coordinate: LocationCoordinate2D, radiusKilometers: Double) async throws -> [Spot] {
        nearbyResult
    }

    func spot(id: UUID) async throws -> Spot? {
        spotResult
    }

    func favoriteSpotIDs() async throws -> Set<UUID> {
        favoriteIDsResult
    }

    func favoriteSpots() async throws -> [Spot] {
        favoriteSpotsResult
    }

    func setFavorite(spotID: UUID, isFavorite: Bool) async throws {}
}

final class SpotRepositoryContractTests: XCTestCase {
    private let spotID = UUID()

    private func makeSpot() -> Spot {
        Spot(
            id: spotID,
            name: "Port de Barcelona",
            category: .sea,
            summary: "Marina y dique del puerto.",
            longitude: 2.1896,
            latitude: 41.3744,
            distanceMeters: nil
        )
    }

    private func makeDouble(
        list: [Spot] = [],
        nearby: [Spot] = [],
        spot: Spot? = nil,
        favoriteIDs: Set<UUID> = [],
        favoriteSpots: [Spot] = []
    ) -> SpotsRepositoryTestDouble {
        SpotsRepositoryTestDouble(
            listResult: list,
            nearbyResult: nearby,
            spotResult: spot,
            favoriteIDsResult: favoriteIDs,
            favoriteSpotsResult: favoriteSpots
        )
    }

    func testDoubleConformsAsAnySpotRepositoryAndEachSeamReturnsCannedValues() async throws {
        let canned = makeSpot()
        let double = makeDouble(
            list: [canned],
            nearby: [canned],
            spot: canned,
            favoriteIDs: [spotID],
            favoriteSpots: [canned]
        )

        let repository: any SpotRepository = double
        let region = SpotRegion(
            center: LocationCoordinate2D(latitude: 41.0, longitude: 2.0),
            latitudinalMeters: 1_000,
            longitudinalMeters: 2_000
        )

        let list = try await repository.listSpots(region: region)
        XCTAssertEqual(list, [canned])

        let nearby = try await repository.nearbySpots(
            from: LocationCoordinate2D(latitude: 41.0, longitude: 2.0),
            radiusKilometers: 10
        )
        XCTAssertEqual(nearby, [canned])

        let spot = try await repository.spot(id: spotID)
        XCTAssertEqual(spot, canned)

        let favoriteIDs = try await repository.favoriteSpotIDs()
        XCTAssertEqual(favoriteIDs, [spotID])

        let favoriteSpots = try await repository.favoriteSpots()
        XCTAssertEqual(favoriteSpots, [canned])

        try await repository.setFavorite(spotID: spotID, isFavorite: true)
    }

    func testEmptyCannedValuesRoundTripAcrossSeams() async throws {
        let double = makeDouble()
        let repository: any SpotRepository = double
        let region = SpotRegion(
            center: LocationCoordinate2D(latitude: 41.0, longitude: 2.0),
            latitudinalMeters: 1_000,
            longitudinalMeters: 2_000
        )

        let list = try await repository.listSpots(region: region)
        XCTAssertTrue(list.isEmpty)

        let nearby = try await repository.nearbySpots(
            from: LocationCoordinate2D(latitude: 41.0, longitude: 2.0),
            radiusKilometers: 50
        )
        XCTAssertTrue(nearby.isEmpty)

        let spot = try await repository.spot(id: spotID)
        XCTAssertNil(spot)

        let favoriteIDs = try await repository.favoriteSpotIDs()
        XCTAssertTrue(favoriteIDs.isEmpty)

        let favoriteSpots = try await repository.favoriteSpots()
        XCTAssertTrue(favoriteSpots.isEmpty)
    }

    func testSpotRepositoryErrorBackendUnavailableIsEquatableAndUsable() async throws {
        let first: SpotRepositoryError = .backendUnavailable
        let second: SpotRepositoryError = .backendUnavailable
        let other: SpotRepositoryError = .queryFailed("démo")

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)

        let sendableError: any Sendable = first
        XCTAssertNotNil(sendableError as? SpotRepositoryError)
    }

    func testSpotRepositoryErrorQueryFailedCarriesDescription() throws {
        let error: SpotRepositoryError = .queryFailed("consulta sin soporte")

        if case let .queryFailed(description) = error {
            XCTAssertEqual(description, "consulta sin soporte")
        } else {
            XCTFail("Se esperaba .queryFailed")
        }
    }

    func testSpotRepositoryErrorAuthenticationRequiredIsUsable() throws {
        let error: SpotRepositoryError = .authenticationRequired
        XCTAssertEqual(error, .authenticationRequired)
        XCTAssertNotEqual(error, .backendUnavailable)
        XCTAssertNotEqual(error, .queryFailed("x"))
    }
}