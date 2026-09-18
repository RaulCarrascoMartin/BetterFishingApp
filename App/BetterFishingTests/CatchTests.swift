import XCTest

@testable import BetterFishing

final class CatchTests: XCTestCase {
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

    private func makeCatch(location: LocationCoordinate2D? = nil, notes: String = "") -> Catch {
        Catch(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            species: makeSpecies(),
            photoPath: "33333333-3333-3333-3333-333333333333.jpg",
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: location,
            notes: notes,
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime + 1)
        )
    }

    func testCatchRoundTripPreservesAllFieldsWithLocationAndNotes() throws {
        let catchEntry = makeCatch(location: makeLocation(), notes: "Capturada cerca del canal")

        let data = try JSONEncoder().encode(catchEntry)
        let decoded = try JSONDecoder().decode(Catch.self, from: data)

        XCTAssertEqual(decoded.id, catchEntry.id)
        XCTAssertEqual(decoded.species, catchEntry.species)
        XCTAssertEqual(decoded.photoPath, catchEntry.photoPath)
        XCTAssertEqual(decoded.date, catchEntry.date)
        XCTAssertEqual(decoded.location, catchEntry.location)
        XCTAssertEqual(decoded.notes, catchEntry.notes)
        XCTAssertEqual(decoded.createdAt, catchEntry.createdAt)
    }

    func testCatchRoundTripPreservesEmbeddedSpeciesFully() throws {
        let catchEntry = makeCatch(location: makeLocation(), notes: "Notas de prueba")

        let data = try JSONEncoder().encode(catchEntry)
        let decoded = try JSONDecoder().decode(Catch.self, from: data)

        XCTAssertEqual(decoded.species.id, "species-largemouth")
        XCTAssertEqual(decoded.species.commonName, "Largemouth Bass")
        XCTAssertEqual(decoded.species.scientificName, "Micropterus salmoides")
        XCTAssertEqual(decoded.species.localizedName, "Lubina americana")
        XCTAssertEqual(
            decoded.species.referenceImageURL,
            URL(string: "https://fishial.example/species/largemouth.jpg")
        )
    }

    func testCatchRoundTripWithoutLocationKeepsLocationNil() throws {
        let catchEntry = makeCatch(location: nil, notes: "Sin ubicación")

        let data = try JSONEncoder().encode(catchEntry)
        let decoded = try JSONDecoder().decode(Catch.self, from: data)

        XCTAssertEqual(decoded.id, catchEntry.id)
        XCTAssertEqual(decoded.photoPath, catchEntry.photoPath)
        XCTAssertEqual(decoded.date, catchEntry.date)
        XCTAssertNil(decoded.location)
        XCTAssertEqual(decoded.notes, catchEntry.notes)
        XCTAssertEqual(decoded.createdAt, catchEntry.createdAt)
    }

    func testCatchLocationCoordinatesPreservedExactly() throws {
        let catchEntry = makeCatch(location: makeLocation())

        let data = try JSONEncoder().encode(catchEntry)
        let decoded = try JSONDecoder().decode(Catch.self, from: data)

        XCTAssertEqual(decoded.location?.latitude, 25.7617)
        XCTAssertEqual(decoded.location?.longitude, -80.1918)
    }

    func testCatchMutableFieldsCanBeReassigned() {
        var catchEntry = makeCatch(location: makeLocation(), notes: "original")
        let newDate = Date(timeIntervalSinceReferenceDate: referenceTime + 86_400)
        let newLocation = LocationCoordinate2D(latitude: 40.44, longitude: -3.68)

        catchEntry.date = newDate
        catchEntry.notes = "editada"
        catchEntry.location = newLocation

        XCTAssertEqual(catchEntry.date, newDate)
        XCTAssertEqual(catchEntry.notes, "editada")
        XCTAssertEqual(catchEntry.location, newLocation)
    }

    func testCatchLocationCanBeClearedToNil() {
        var catchEntry = makeCatch(location: makeLocation(), notes: "con ubicación")

        catchEntry.location = nil

        XCTAssertNil(catchEntry.location)
    }

    func testLocationCoordinate2DCodableRoundTrip() throws {
        let location = makeLocation()

        let data = try JSONEncoder().encode(location)
        let decoded = try JSONDecoder().decode(LocationCoordinate2D.self, from: data)

        XCTAssertEqual(decoded, location)
        XCTAssertEqual(decoded.latitude, 25.7617)
        XCTAssertEqual(decoded.longitude, -80.1918)
    }
}