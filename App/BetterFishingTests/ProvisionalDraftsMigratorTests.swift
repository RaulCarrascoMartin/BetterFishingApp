import XCTest

@testable import BetterFishing

final class ProvisionalDraftsMigratorTests: XCTestCase {
    private let referenceTime: TimeInterval = 900_000_000

    private func makeSpecies(
        id: String,
        commonName: String,
        scientificName: String
    ) -> Species {
        Species(
            id: id,
            commonName: commonName,
            scientificName: scientificName,
            localizedName: "Nombre localizado",
            referenceImageURL: URL(string: "https://fishial.example/species/\(id).jpg")
        )
    }

    private func makePhotoData(_ byte: UInt8) -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, byte, 0x2A, 0x2A])
    }

    private func makeDraft(
        id: UUID,
        species: Species,
        createdAt: Date,
        photoPath: String? = nil
    ) -> CatchDraft {
        CatchDraft(
            id: id,
            species: species,
            photoPath: photoPath ?? "\(id.uuidString).jpg",
            createdAt: createdAt,
            status: .draft
        )
    }

    private func writeDraft(
        to directory: URL,
        draft: CatchDraft,
        photoData: Data
    ) throws {
        let photoURL = directory.appendingPathComponent(draft.photoPath)
        try photoData.write(to: photoURL, options: .atomic)
        let jsonURL = directory.appendingPathComponent("\(draft.id.uuidString).json")
        try JSONEncoder().encode(draft).write(to: jsonURL, options: .atomic)
    }

    private func makeDraftsMigrator(
        repository: any CatchRepository,
        draftsDirectory: URL
    ) -> ProvisionalDraftsMigrator {
        ProvisionalDraftsMigrator(
            catchRepository: repository,
            draftsDirectory: draftsDirectory
        )
    }

    func testMigratesValidDraftsIntoCatchesPreservingSpeciesPhotoAndDate() async throws {
        let draftsDirectory = try makeTemporaryDirectory()
        let repositoryDirectory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: repositoryDirectory.url)

        let firstSpecies = makeSpecies(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
        let secondSpecies = makeSpecies(
            id: "species-snook",
            commonName: "Common Snook",
            scientificName: "Centropomus undecimalis"
        )
        let firstDate = Date(timeIntervalSinceReferenceDate: referenceTime)
        let secondDate = Date(timeIntervalSinceReferenceDate: referenceTime + 3600)
        let firstPhoto = makePhotoData(0x01)
        let secondPhoto = makePhotoData(0x02)

        let firstDraft = makeDraft(id: UUID(), species: firstSpecies, createdAt: firstDate)
        let secondDraft = makeDraft(id: UUID(), species: secondSpecies, createdAt: secondDate)
        try writeDraft(to: draftsDirectory.url, draft: firstDraft, photoData: firstPhoto)
        try writeDraft(to: draftsDirectory.url, draft: secondDraft, photoData: secondPhoto)

        try await makeDraftsMigrator(
            repository: repository,
            draftsDirectory: draftsDirectory.url
        ).migrateIfNeeded()

        let catches = try await repository.listCatches()
        XCTAssertEqual(catches.count, 2)

        let firstCatch = try XCTUnwrap(catches.first { $0.species.id == firstSpecies.id })
        XCTAssertEqual(firstCatch.species, firstSpecies)
        XCTAssertEqual(firstCatch.species.id, "species-largemouth")
        XCTAssertEqual(firstCatch.species.commonName, "Largemouth Bass")
        XCTAssertEqual(firstCatch.species.scientificName, "Micropterus salmoides")
        XCTAssertEqual(firstCatch.date, firstDate)
        XCTAssertNil(firstCatch.location)
        XCTAssertEqual(firstCatch.notes, "")
        XCTAssertEqual(repository.photoData(for: firstCatch), firstPhoto)

        let secondCatch = try XCTUnwrap(catches.first { $0.species.id == secondSpecies.id })
        XCTAssertEqual(secondCatch.species, secondSpecies)
        XCTAssertEqual(secondCatch.species.id, "species-snook")
        XCTAssertEqual(secondCatch.species.commonName, "Common Snook")
        XCTAssertEqual(secondCatch.species.scientificName, "Centropomus undecimalis")
        XCTAssertEqual(secondCatch.date, secondDate)
        XCTAssertNil(secondCatch.location)
        XCTAssertEqual(secondCatch.notes, "")
        XCTAssertEqual(repository.photoData(for: secondCatch), secondPhoto)

        let markerURL = draftsDirectory.url.appendingPathComponent(".migrated")
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: draftsDirectory.url.appendingPathComponent("\(firstDraft.id.uuidString).json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: draftsDirectory.url.appendingPathComponent(firstDraft.photoPath).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: draftsDirectory.url.appendingPathComponent("\(secondDraft.id.uuidString).json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: draftsDirectory.url.appendingPathComponent(secondDraft.photoPath).path
        ))
    }

    func testSecondMigrateIfNeededDoesNotDuplicateCatches() async throws {
        let draftsDirectory = try makeTemporaryDirectory()
        let repositoryDirectory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: repositoryDirectory.url)

        let draft = makeDraft(
            id: UUID(),
            species: makeSpecies(
                id: "species-largemouth",
                commonName: "Largemouth Bass",
                scientificName: "Micropterus salmoides"
            ),
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime)
        )
        try writeDraft(to: draftsDirectory.url, draft: draft, photoData: makePhotoData(0x01))

        let migrator = makeDraftsMigrator(
            repository: repository,
            draftsDirectory: draftsDirectory.url
        )

        try await migrator.migrateIfNeeded()
        let firstMigrationCount = try await repository.listCatches().count
        XCTAssertEqual(firstMigrationCount, 1)

        try await migrator.migrateIfNeeded()
        let secondMigrationCount = try await repository.listCatches().count
        XCTAssertEqual(secondMigrationCount, 1)
    }

    func testCorruptDraftJSONIsSkippedWhileValidDraftsAreConverted() async throws {
        let draftsDirectory = try makeTemporaryDirectory()
        let repositoryDirectory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: repositoryDirectory.url)

        let validSpecies = makeSpecies(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
        let validDraft = makeDraft(
            id: UUID(),
            species: validSpecies,
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime)
        )
        try writeDraft(to: draftsDirectory.url, draft: validDraft, photoData: makePhotoData(0x01))

        let corruptID = UUID()
        let corruptURL = draftsDirectory.url.appendingPathComponent("\(corruptID.uuidString).json")
        try Data("not-a-valid-draft-json".utf8).write(to: corruptURL)

        try await makeDraftsMigrator(
            repository: repository,
            draftsDirectory: draftsDirectory.url
        ).migrateIfNeeded()

        let catches = try await repository.listCatches()
        XCTAssertEqual(catches.count, 1)
        XCTAssertEqual(catches.first?.species.id, validSpecies.id)
        XCTAssertEqual(catches.first?.date, validDraft.createdAt)

        let markerURL = draftsDirectory.url.appendingPathComponent(".migrated")
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testDraftWithMissingPhotoIsSkippedWhileOthersAreConverted() async throws {
        let draftsDirectory = try makeTemporaryDirectory()
        let repositoryDirectory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: repositoryDirectory.url)

        let missingPhotoSpecies = makeSpecies(
            id: "species-tarpon",
            commonName: "Tarpon",
            scientificName: "Megalops atlanticus"
        )
        let missingPhotoDraft = makeDraft(
            id: UUID(),
            species: missingPhotoSpecies,
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime)
        )
        let jsonURL = draftsDirectory.url.appendingPathComponent("\(missingPhotoDraft.id.uuidString).json")
        try JSONEncoder().encode(missingPhotoDraft).write(to: jsonURL, options: .atomic)

        let validSpecies = makeSpecies(
            id: "species-snook",
            commonName: "Common Snook",
            scientificName: "Centropomus undecimalis"
        )
        let validDraft = makeDraft(
            id: UUID(),
            species: validSpecies,
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime + 600)
        )
        try writeDraft(to: draftsDirectory.url, draft: validDraft, photoData: makePhotoData(0x02))

        try await makeDraftsMigrator(
            repository: repository,
            draftsDirectory: draftsDirectory.url
        ).migrateIfNeeded()

        let catches = try await repository.listCatches()
        XCTAssertEqual(catches.count, 1)
        XCTAssertEqual(catches.first?.species.id, validSpecies.id)

        let markerURL = draftsDirectory.url.appendingPathComponent(".migrated")
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testMigrateIsNoOpWhenDraftsDirectoryDoesNotExist() async throws {
        let temporary = try makeTemporaryDirectory()
        let draftsDirectory = temporary.url.appendingPathComponent("MissingDrafts", isDirectory: true)
        let repositoryDirectory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: repositoryDirectory.url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: draftsDirectory.path))

        try await makeDraftsMigrator(
            repository: repository,
            draftsDirectory: draftsDirectory
        ).migrateIfNeeded()

        XCTAssertFalse(FileManager.default.fileExists(atPath: draftsDirectory.path))
        let catches = try await repository.listCatches()
        XCTAssertTrue(catches.isEmpty)
    }

    func testMigrateIsNoOpWhenMarkerAlreadyExists() async throws {
        let draftsDirectory = try makeTemporaryDirectory()
        let repositoryDirectory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: repositoryDirectory.url)

        let draft = makeDraft(
            id: UUID(),
            species: makeSpecies(
                id: "species-largemouth",
                commonName: "Largemouth Bass",
                scientificName: "Micropterus salmoides"
            ),
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime)
        )
        try writeDraft(to: draftsDirectory.url, draft: draft, photoData: makePhotoData(0x01))
        FileManager.default.createFile(
            atPath: draftsDirectory.url.appendingPathComponent(".migrated").path,
            contents: nil
        )

        try await makeDraftsMigrator(
            repository: repository,
            draftsDirectory: draftsDirectory.url
        ).migrateIfNeeded()

        let catches = try await repository.listCatches()
        XCTAssertTrue(catches.isEmpty)
    }
}