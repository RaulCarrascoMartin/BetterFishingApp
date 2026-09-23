import Foundation
import XCTest

@testable import BetterFishing

final class SpotModelsTests: XCTestCase {
    private let spotID = "11111111-1111-1111-1111-111111111111"
    private let nearbyRowJSON = """
    {
        "id": "11111111-1111-1111-1111-111111111111",
        "name": "Port de Barcelona",
        "category": "sea",
        "summary": "Marina y dique del puerto.",
        "longitude": 2.1896,
        "latitude": 41.3744,
        "distance_m": 1234.5
    }
    """

    func testSpotRoundTripWithDistanceMetersPresentDecodesSnakeCaseDistance() throws {
        let spot = try JSONDecoder().decode(Spot.self, from: Data(nearbyRowJSON.utf8))

        XCTAssertEqual(spot.id.uuidString, spotID)
        XCTAssertEqual(spot.name, "Port de Barcelona")
        XCTAssertEqual(spot.category, .sea)
        XCTAssertEqual(spot.summary, "Marina y dique del puerto.")
        XCTAssertEqual(spot.longitude, 2.1896)
        XCTAssertEqual(spot.latitude, 41.3744)
        XCTAssertEqual(spot.distanceMeters, 1234.5)

        let data = try JSONEncoder().encode(spot)
        let decoded = try JSONDecoder().decode(Spot.self, from: data)
        XCTAssertEqual(decoded, spot)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["distance_m"] as? Double, 1234.5)
        XCTAssertNil(object["distanceMeters"])
    }

    func testNearbySpotsRowContractDecodesArrayOfSpots() throws {
        let json = "[\(nearbyRowJSON)]"
        let spots = try JSONDecoder().decode([Spot].self, from: Data(json.utf8))

        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(spots[0].distanceMeters, 1234.5)
        XCTAssertEqual(spots[0].category, .sea)
        XCTAssertEqual(spots[0].coordinate.latitude, 41.3744)
        XCTAssertEqual(spots[0].coordinate.longitude, 2.1896)
    }

    func testSpotRoundTripWithoutDistanceMetersYieldsNilAndOmitsKey() throws {
        let bareJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Embalse de Sau",
            "category": "lake",
            "summary": "Amplia lámina de agua.",
            "longitude": 2.2486,
            "latitude": 42.0037
        }
        """
        let spot = try JSONDecoder().decode(Spot.self, from: Data(bareJSON.utf8))

        XCTAssertNil(spot.distanceMeters)

        let data = try JSONEncoder().encode(spot)
        let decoded = try JSONDecoder().decode(Spot.self, from: data)
        XCTAssertEqual(decoded, spot)
        XCTAssertNil(decoded.distanceMeters)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["distance_m"])
        XCTAssertEqual(Set(object.keys), ["id", "name", "category", "summary", "longitude", "latitude"])
    }

    func testSpotCoordinateDerivesFromLatitudeAndLongitude() throws {
        let spot = try makeSpot(distanceMeters: nil)

        XCTAssertEqual(spot.coordinate.latitude, spot.latitude)
        XCTAssertEqual(spot.coordinate.longitude, spot.longitude)
        XCTAssertEqual(
            spot.coordinate,
            LocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        )
    }

    func testSpotEquatableSemantics() throws {
        let spot = try makeSpot(distanceMeters: 100)
        let equal = try makeSpot(distanceMeters: 100)
        let differentDistance = try makeSpot(distanceMeters: 150)

        XCTAssertEqual(spot, equal)
        XCTAssertNotEqual(spot, differentDistance)
    }

    func testSpotCategoryRawValuesAndRoundTrip() throws {
        XCTAssertEqual(SpotCategory.river.rawValue, "river")
        XCTAssertEqual(SpotCategory.lake.rawValue, "lake")
        XCTAssertEqual(SpotCategory.sea.rawValue, "sea")
        XCTAssertEqual(SpotCategory.shore.rawValue, "shore")
        XCTAssertEqual(SpotCategory.allCases, [.river, .lake, .sea, .shore])

        for category in SpotCategory.allCases {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(SpotCategory.self, from: data)
            XCTAssertEqual(decoded, category)
            XCTAssertEqual(decoded.rawValue, category.rawValue)
        }
    }

    func testSpotRegionCornersDerivedFromCenterAndMeters() {
        let latitude = 41.0
        let longitude = 2.0
        let latitudinalMeters = 111_320.0
        let cosLatitude = cos(latitude * .pi / 180)
        let longitudinalMeters = 111_320.0 * cosLatitude

        let region = SpotRegion(
            center: LocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: latitudinalMeters,
            longitudinalMeters: longitudinalMeters
        )

        XCTAssertEqual(region.minLatitude, 40.5, accuracy: 0.000_001)
        XCTAssertEqual(region.maxLatitude, 41.5, accuracy: 0.000_001)
        XCTAssertEqual(region.minLongitude, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(region.maxLongitude, 2.5, accuracy: 0.000_001)
    }

    func testSpotRegionEquatable() {
        let regionA = SpotRegion(
            center: LocationCoordinate2D(latitude: 41.0, longitude: 2.0),
            latitudinalMeters: 1_000,
            longitudinalMeters: 2_000
        )
        let regionB = SpotRegion(
            center: LocationCoordinate2D(latitude: 41.0, longitude: 2.0),
            latitudinalMeters: 1_000,
            longitudinalMeters: 2_000
        )
        let regionC = SpotRegion(
            center: LocationCoordinate2D(latitude: 42.0, longitude: 3.0),
            latitudinalMeters: 1_000,
            longitudinalMeters: 2_000
        )

        XCTAssertEqual(regionA, regionB)
        XCTAssertNotEqual(regionA, regionC)
    }

    // MARK: - Helpers

    private func makeSpot(distanceMeters: Double?) throws -> Spot {
        let id = try XCTUnwrap(UUID(uuidString: spotID))
        return Spot(
            id: id,
            name: "Port de Barcelona",
            category: .sea,
            summary: "Marina y dique del puerto.",
            longitude: 2.1896,
            latitude: 41.3744,
            distanceMeters: distanceMeters
        )
    }
}