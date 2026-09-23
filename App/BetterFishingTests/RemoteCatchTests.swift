import XCTest

@testable import BetterFishing

final class RemoteCatchTests: XCTestCase {
    private let referenceTime: TimeInterval = 800_000_000

    private func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides",
            localizedName: "Lubina americana",
            referenceImageURL: URL(string: "https://fishial.example/species/largemouth.jpg")
        )
    }

    private func makeLocation() -> LocationCoordinate2D {
        LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
    }

    private func makeRemoteCatch(photoPath: String?) -> RemoteCatch {
        RemoteCatch(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            userID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            species: makeSpecies(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: makeLocation(),
            notes: "Capturada cerca del canal",
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime + 1),
            updatedAt: Date(timeIntervalSinceReferenceDate: referenceTime + 2),
            photoPath: photoPath
        )
    }

    func testRoundTripCodableWithSpeciesAndLocation() throws {
        let remote = makeRemoteCatch(photoPath: "33333333-3333-3333-3333-333333333333.jpg")

        let data = try JSONEncoder().encode(remote)
        let decoded = try JSONDecoder().decode(RemoteCatch.self, from: data)

        XCTAssertEqual(decoded, remote)
        XCTAssertEqual(decoded.id, remote.id)
        XCTAssertEqual(decoded.userID, remote.userID)
        XCTAssertEqual(decoded.species, remote.species)
        XCTAssertEqual(decoded.date, remote.date)
        XCTAssertEqual(decoded.location, remote.location)
        XCTAssertEqual(decoded.notes, remote.notes)
        XCTAssertEqual(decoded.createdAt, remote.createdAt)
        XCTAssertEqual(decoded.updatedAt, remote.updatedAt)
        XCTAssertEqual(decoded.photoPath, remote.photoPath)
    }

    func testDecodesSnakeCaseJSONPayload() throws {
        let payload = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "user_id": "44444444-4444-4444-4444-444444444444",
          "species": {
            "id": "species-largemouth",
            "commonName": "Largemouth Bass",
            "scientificName": "Micropterus salmoides"
          },
          "date": 800000000,
          "location": { "latitude": 25.7617, "longitude": -80.1918 },
          "notes": "Capturada cerca del canal",
          "created_at": 800000001,
          "updated_at": 800000002,
          "photo_path": "33333333-3333-3333-3333-333333333333.jpg"
        }
        """

        let decoded = try JSONDecoder().decode(RemoteCatch.self, from: Data(payload.utf8))

        XCTAssertEqual(
            decoded.id,
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")
        )
        XCTAssertEqual(
            decoded.userID,
            UUID(uuidString: "44444444-4444-4444-4444-444444444444")
        )
        XCTAssertEqual(decoded.species.id, "species-largemouth")
        XCTAssertEqual(decoded.species.commonName, "Largemouth Bass")
        XCTAssertEqual(decoded.species.scientificName, "Micropterus salmoides")
        XCTAssertEqual(decoded.species.localizedName, nil)
        XCTAssertEqual(decoded.date, Date(timeIntervalSinceReferenceDate: referenceTime))
        XCTAssertEqual(decoded.location, makeLocation())
        XCTAssertEqual(decoded.notes, "Capturada cerca del canal")
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSinceReferenceDate: referenceTime + 1))
        XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSinceReferenceDate: referenceTime + 2))
        XCTAssertEqual(
            decoded.photoPath,
            "33333333-3333-3333-3333-333333333333.jpg"
        )
    }

    func testAsCatchPreservesIDAndFallsBackPhotoPathWhenNil() async throws {
        let remote = makeRemoteCatch(photoPath: nil)

        let local = try await remote.asCatch()

        XCTAssertEqual(local.id, remote.id)
        XCTAssertEqual(local.species, remote.species)
        XCTAssertEqual(local.date, remote.date)
        XCTAssertEqual(local.location, remote.location)
        XCTAssertEqual(local.notes, remote.notes)
        XCTAssertEqual(local.createdAt, remote.createdAt)
        XCTAssertEqual(local.photoPath, "33333333-3333-3333-3333-333333333333.jpg")
    }

    func testAsCatchPreservesProvidedPhotoPath() async throws {
        let remote = makeRemoteCatch(photoPath: "custom/foto.jpg")

        let local = try await remote.asCatch()

        XCTAssertEqual(local.id, remote.id)
        XCTAssertEqual(local.photoPath, "custom/foto.jpg")
    }
}