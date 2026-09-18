import XCTest

@testable import BetterFishing

final class LocalFileCatchRepositoryTests: XCTestCase {
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

    private func makePhotoData() -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x2A, 0x2A])
    }

    func testSaveWritesExactlyJPGAndJSONFilesWithPhotoBytesAndDecodesMetadata() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let species = makeSpecies()
        let photoData = makePhotoData()
        let date = Date(timeIntervalSinceReferenceDate: referenceTime)
        let location = makeLocation()

        let saved = try await repository.saveCatch(
            species: species,
            photoData: photoData,
            date: date,
            location: location,
            notes: "Capturada cerca del canal"
        )

        let photoURL = directory.url.appendingPathComponent("\(saved.id.uuidString).jpg")
        let jsonURL = directory.url.appendingPathComponent("\(saved.id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
        XCTAssertEqual(files.count, 2)

        XCTAssertEqual(try Data(contentsOf: photoURL), photoData)

        let decoded = try JSONDecoder().decode(Catch.self, from: Data(contentsOf: jsonURL))
        XCTAssertEqual(decoded.id, saved.id)
        XCTAssertEqual(decoded.species, species)
        XCTAssertEqual(decoded.photoPath, "\(saved.id.uuidString).jpg")
        XCTAssertEqual(decoded.date, date)
        XCTAssertEqual(decoded.location, location)
        XCTAssertEqual(decoded.notes, "Capturada cerca del canal")
        XCTAssertEqual(decoded.createdAt, saved.createdAt)
    }

    func testSecondInstanceReReadsSameCatchAndPhoto() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let photoData = makePhotoData()
        let date = Date(timeIntervalSinceReferenceDate: referenceTime)
        let location = makeLocation()

        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: photoData,
            date: date,
            location: location,
            notes: "Persistente"
        )

        let otherRepository = LocalFileCatchRepository(directoryURL: directory.url)
        let listed = try await otherRepository.listCatches()

        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.id, saved.id)
        XCTAssertEqual(listed.first?.species, saved.species)
        XCTAssertEqual(listed.first?.photoPath, saved.photoPath)
        XCTAssertEqual(listed.first?.date, saved.date)
        XCTAssertEqual(listed.first?.location, saved.location)
        XCTAssertEqual(listed.first?.notes, saved.notes)
        XCTAssertEqual(listed.first?.createdAt, saved.createdAt)

        let fetched = try await otherRepository.getCatch(id: saved.id)
        XCTAssertEqual(fetched?.id, saved.id)
        XCTAssertEqual(fetched?.species, saved.species)
        XCTAssertEqual(fetched?.date, saved.date)
        XCTAssertEqual(fetched?.location, saved.location)
        XCTAssertEqual(fetched?.notes, saved.notes)
        XCTAssertEqual(fetched?.createdAt, saved.createdAt)

        XCTAssertEqual(otherRepository.photoData(for: saved), photoData)
    }

    func testListReturnsSavedCatchesSortedNewestFirst() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let olderDate = Date(timeIntervalSinceReferenceDate: referenceTime)
        let newerDate = Date(timeIntervalSinceReferenceDate: referenceTime + 86_400)

        let older = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: olderDate,
            location: nil,
            notes: "vieja"
        )
        let newer = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: newerDate,
            location: nil,
            notes: "nueva"
        )

        let listed = try await repository.listCatches()

        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(listed.first?.id, newer.id)
        XCTAssertEqual(listed.last?.id, older.id)
    }

    func testGetReturnsCatchAndNilForUnknown() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let date = Date(timeIntervalSinceReferenceDate: referenceTime)

        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: date,
            location: nil,
            notes: ""
        )

        let fetched = try await repository.getCatch(id: saved.id)
        XCTAssertEqual(fetched?.id, saved.id)
        XCTAssertEqual(fetched?.species, saved.species)
        XCTAssertEqual(fetched?.date, date)
        XCTAssertNil(fetched?.location)
        XCTAssertEqual(fetched?.notes, "")
        XCTAssertEqual(fetched?.createdAt, saved.createdAt)

        let missing = try await repository.getCatch(id: UUID())
        XCTAssertNil(missing)
    }

    func testUpdateChangesDateLocationNotesAndKeepsSpeciesPhotoAndCreation() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let photoData = makePhotoData()

        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: photoData,
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: "original"
        )
        let newDate = Date(timeIntervalSinceReferenceDate: referenceTime + 2 * 86_400)
        let newLocation = makeLocation()

        try await repository.updateCatch(id: saved.id, date: newDate, location: newLocation, notes: "editada")

        let updated = try await repository.getCatch(id: saved.id)
        XCTAssertEqual(updated?.date, newDate)
        XCTAssertEqual(updated?.location, newLocation)
        XCTAssertEqual(updated?.notes, "editada")
        XCTAssertEqual(updated?.species, saved.species)
        XCTAssertEqual(updated?.photoPath, saved.photoPath)
        XCTAssertEqual(updated?.createdAt, saved.createdAt)

        XCTAssertEqual(repository.photoData(for: try XCTUnwrap(updated)), photoData)

        let otherRepository = LocalFileCatchRepository(directoryURL: directory.url)
        let refreshed = try await otherRepository.getCatch(id: saved.id)
        XCTAssertEqual(refreshed?.date, newDate)
        XCTAssertEqual(refreshed?.location, newLocation)
        XCTAssertEqual(refreshed?.notes, "editada")
    }

    func testUpdateWithNilKeepsDateAndNotesAndClearsLocation() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let originalDate = Date(timeIntervalSinceReferenceDate: referenceTime)

        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: originalDate,
            location: makeLocation(),
            notes: "conservada"
        )

        try await repository.updateCatch(id: saved.id, date: nil, location: nil, notes: nil)

        let updated = try await repository.getCatch(id: saved.id)
        XCTAssertEqual(updated?.date, originalDate)
        XCTAssertNil(updated?.location)
        XCTAssertEqual(updated?.notes, "conservada")
        XCTAssertEqual(updated?.species, saved.species)
    }

    func testDeleteRemovesBothFilesAndExcludesFromList() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: directory.url)

        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )

        try await repository.deleteCatch(id: saved.id)

        let photoURL = directory.url.appendingPathComponent("\(saved.id.uuidString).jpg")
        let jsonURL = directory.url.appendingPathComponent("\(saved.id.uuidString).json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        let fetched = try await repository.getCatch(id: saved.id)
        XCTAssertNil(fetched)

        let listed = try await repository.listCatches()
        XCTAssertTrue(listed.isEmpty)
    }

    func testDeleteSucceedsWhenPhotoFileIsMissing() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: directory.url)

        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )
        let photoURL = directory.url.appendingPathComponent("\(saved.id.uuidString).jpg")
        try FileManager.default.removeItem(at: photoURL)

        try await repository.deleteCatch(id: saved.id)

        let jsonURL = directory.url.appendingPathComponent("\(saved.id.uuidString).json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        let fetched = try await repository.getCatch(id: saved.id)
        XCTAssertNil(fetched)
    }

    func testSaveIntoUnwritablePathThrowsWriteFailed() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("blocked-path")
        try Data("blocker".utf8).write(to: fileURL)
        let repository = LocalFileCatchRepository(directoryURL: fileURL)

        do {
            _ = try await repository.saveCatch(
                species: makeSpecies(),
                photoData: makePhotoData(),
                date: Date(timeIntervalSinceReferenceDate: referenceTime),
                location: nil,
                notes: ""
            )
            XCTFail("saveCatch debería lanzar CatchSaveError.writeFailed")
        } catch {
            XCTAssertEqual(error as? CatchSaveError, .writeFailed)
        }
    }

    func testPhotoDataReturnsNilForMissingFileAndDataForExisting() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let photoData = makePhotoData()

        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: photoData,
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )

        XCTAssertEqual(repository.photoData(for: saved), photoData)

        let phantom = Catch(
            id: UUID(),
            species: makeSpecies(),
            photoPath: "\(UUID().uuidString).jpg",
            date: Date(),
            location: nil,
            notes: "",
            createdAt: Date()
        )
        XCTAssertNil(repository.photoData(for: phantom))
    }
}