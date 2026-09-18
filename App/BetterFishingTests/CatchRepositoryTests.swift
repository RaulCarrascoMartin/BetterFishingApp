import XCTest

@testable import BetterFishing

final class CatchRepositoryTests: XCTestCase {
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

    private func makeStripedBass() -> Species {
        Species(
            id: "species-striped-bass",
            commonName: "Striped Bass",
            scientificName: "Morone saxatilis",
            localizedName: "Lubina rayada"
        )
    }

    private func makeLocation() -> LocationCoordinate2D {
        LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
    }

    private func makePhotoData() -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    }

    func testSaveReturnsCatchWithPassedFields() async throws {
        let fake = CatchRepositoryFake()
        let repository: any CatchRepository = fake
        let species = makeSpecies()
        let photoData = makePhotoData()
        let date = Date(timeIntervalSinceReferenceDate: referenceTime)
        let location = makeLocation()
        let notes = "Capturada cerca del canal"

        let saved = try await repository.saveCatch(
            species: species,
            photoData: photoData,
            date: date,
            location: location,
            notes: notes
        )

        XCTAssertEqual(saved.species, species)
        XCTAssertEqual(saved.date, date)
        XCTAssertEqual(saved.location, location)
        XCTAssertEqual(saved.notes, notes)
        XCTAssertEqual(saved.photoPath, "\(saved.id.uuidString).jpg")
        XCTAssertEqual(fake.receivedSpecies, [species])
        XCTAssertEqual(fake.receivedPhotoData, [photoData])
        XCTAssertEqual(fake.receivedDates, [date])
        XCTAssertEqual(fake.receivedLocations, [location])
        XCTAssertEqual(fake.receivedNotes, [notes])
        XCTAssertEqual(fake.receivedSaveIDs, [saved.id])
    }

    func testListReturnsSavedCatches() async throws {
        let repository: any CatchRepository = CatchRepositoryFake()
        let bass = makeSpecies()
        let stripedBass = makeStripedBass()

        _ = try await repository.saveCatch(
            species: bass,
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )
        _ = try await repository.saveCatch(
            species: stripedBass,
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime + 1),
            location: nil,
            notes: ""
        )

        let listed = try await repository.listCatches()

        XCTAssertEqual(listed.count, 2)
        XCTAssertTrue(listed.contains { $0.species == bass })
        XCTAssertTrue(listed.contains { $0.species == stripedBass })
    }

    func testGetReturnsRightCatchById() async throws {
        let repository: any CatchRepository = CatchRepositoryFake()
        let first = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: "primera"
        )
        let second = try await repository.saveCatch(
            species: makeStripedBass(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime + 1),
            location: nil,
            notes: "segunda"
        )

        let fetched = try await repository.getCatch(id: second.id)

        XCTAssertEqual(fetched?.id, second.id)
        XCTAssertEqual(fetched?.species, second.species)
        XCTAssertEqual(fetched?.notes, "segunda")
        let missing = try await repository.getCatch(id: UUID())
        XCTAssertNil(missing)
    }

    func testUpdateChangesDateLocationAndNotes() async throws {
        let repository: any CatchRepository = CatchRepositoryFake()
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: "original"
        )
        let newDate = Date(timeIntervalSinceReferenceDate: referenceTime + 86_400)
        let newLocation = makeLocation()

        try await repository.updateCatch(id: saved.id, date: newDate, location: newLocation, notes: "editada")

        let updated = try await repository.getCatch(id: saved.id)
        XCTAssertEqual(updated?.date, newDate)
        XCTAssertEqual(updated?.location, newLocation)
        XCTAssertEqual(updated?.notes, "editada")
        XCTAssertEqual(updated?.species, saved.species)
    }

    func testDeleteRemovesCatch() async throws {
        let repository: any CatchRepository = CatchRepositoryFake()
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )

        try await repository.deleteCatch(id: saved.id)

        let listed = try await repository.listCatches()
        XCTAssertTrue(listed.isEmpty)
        let fetched = try await repository.getCatch(id: saved.id)
        XCTAssertNil(fetched)
    }

    func testSaveStubFailureThrows() async {
        let fake = CatchRepositoryFake()
        fake.saveStub = .failure(CatchRepositoryFakeError.saveFailed)
        let repository: any CatchRepository = fake

        do {
            _ = try await repository.saveCatch(
                species: makeSpecies(),
                photoData: makePhotoData(),
                date: Date(timeIntervalSinceReferenceDate: referenceTime),
                location: nil,
                notes: ""
            )
            XCTFail("saveCatch debería lanzar el stub de fallo")
        } catch {
            XCTAssertEqual(error as? CatchRepositoryFakeError, .saveFailed)
        }
    }

    func testUpdateStubFailureThrowsAndKeepsCatch() async throws {
        let fake = CatchRepositoryFake()
        let saved = try await fake.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: "original"
        )
        fake.updateStub = .failure(CatchRepositoryFakeError.updateFailed)
        let repository: any CatchRepository = fake

        do {
            try await repository.updateCatch(id: saved.id, date: nil, location: makeLocation(), notes: "editada")
            XCTFail("updateCatch debería lanzar el stub de fallo")
        } catch {
            XCTAssertEqual(error as? CatchRepositoryFakeError, .updateFailed)
        }

        let unchanged = try await repository.getCatch(id: saved.id)
        XCTAssertEqual(unchanged?.notes, "original")
        XCTAssertNil(unchanged?.location)
    }

    func testDeleteStubFailureThrowsAndKeepsCatch() async throws {
        let fake = CatchRepositoryFake()
        let saved = try await fake.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )
        fake.deleteStub = .failure(CatchRepositoryFakeError.deleteFailed)
        let repository: any CatchRepository = fake

        do {
            try await repository.deleteCatch(id: saved.id)
            XCTFail("deleteCatch debería lanzar el stub de fallo")
        } catch {
            XCTAssertEqual(error as? CatchRepositoryFakeError, .deleteFailed)
        }

        let preserved = try await repository.getCatch(id: saved.id)
        XCTAssertNotNil(preserved)
    }
}