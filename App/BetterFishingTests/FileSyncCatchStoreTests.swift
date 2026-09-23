import XCTest

@testable import BetterFishing

final class FileSyncCatchStoreTests: XCTestCase {
    private let referenceTime: TimeInterval = 800_000_000

    private func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
    }

    private func makeCatch(id: UUID) -> Catch {
        Catch(
            id: id,
            species: makeSpecies(),
            photoPath: "\(id.uuidString).jpg",
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
            notes: "Descargada de la cuenta",
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime + 1)
        )
    }

    func testImportCatchWithFixedIDIsReadableByCatchRepository() async throws {
        let directory = try makeTemporaryDirectory()
        let id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let store = FileSyncCatchStore(directoryURL: directory.url)
        let entry = makeCatch(id: id)

        try await store.importCatch(entry, photoData: nil)

        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let listed = try await repository.listCatches()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.id, id)
        XCTAssertEqual(listed.first?.species, entry.species)
        XCTAssertEqual(listed.first?.photoPath, entry.photoPath)
        XCTAssertEqual(listed.first?.notes, entry.notes)
    }

    func testImportWithoutPhotoProducesNilThumbnail() async throws {
        let directory = try makeTemporaryDirectory()
        let id = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let store = FileSyncCatchStore(directoryURL: directory.url)

        try await store.importCatch(makeCatch(id: id), photoData: nil)

        let photo = await store.photoData(for: id)
        XCTAssertNil(photo)

        let local = try await store.localCatch(id: id)
        XCTAssertEqual(local?.id, id)
        XCTAssertEqual(local?.photoPath, "\(id.uuidString).jpg")
    }

    func testImportWithPhotoWritesJPG() async throws {
        let directory = try makeTemporaryDirectory()
        let id = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let store = FileSyncCatchStore(directoryURL: directory.url)
        let photoData = Data([0x01, 0x02, 0x03, 0x04])

        try await store.importCatch(makeCatch(id: id), photoData: photoData)

        let photo = await store.photoData(for: id)
        XCTAssertEqual(photo, photoData)

        let photoURL = directory.url.appendingPathComponent("\(id.uuidString).jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL.path))
    }

    func testImportNeverOverwritesAnotherIDJSON() async throws {
        let directory = try makeTemporaryDirectory()
        let idA = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let idB = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let store = FileSyncCatchStore(directoryURL: directory.url)

        try await store.importCatch(makeCatch(id: idA), photoData: nil)
        try await store.importCatch(makeCatch(id: idB), photoData: nil)

        let localA = try await store.localCatch(id: idA)
        let localB = try await store.localCatch(id: idB)
        XCTAssertEqual(localA?.id, idA)
        XCTAssertEqual(localB?.id, idB)
        XCTAssertEqual(localA?.notes, "Descargada de la cuenta")

        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let catchA = try await repository.getCatch(id: idA)
        let catchB = try await repository.getCatch(id: idB)
        XCTAssertNotNil(catchA)
        XCTAssertNotNil(catchB)
    }

    func testImportPhotoFailureLeavesConsistentJSONNoOrphan() async throws {
        let directory = try makeTemporaryDirectory()
        let id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let store = FileSyncCatchStore(directoryURL: directory.url)
        try FileManager.default.createDirectory(
            at: directory.url.appendingPathComponent("\(id.uuidString).jpg"),
            withIntermediateDirectories: true
        )

        do {
            try await store.importCatch(makeCatch(id: id), photoData: Data([0x01, 0x02]))
            XCTFail("importCatch debería lanzar SyncCatchStoreError.writeFailed")
        } catch {
            XCTAssertEqual(error as? SyncCatchStoreError, .writeFailed)
        }

        let jsonURL = directory.url.appendingPathComponent("\(id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))
        let decoded = try JSONDecoder().decode(Catch.self, from: Data(contentsOf: jsonURL))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.notes, "Descargada de la cuenta")
    }

    func testLocalModificationDateNilWhenAbsentAndPresentWhenFileExists() async throws {
        let directory = try makeTemporaryDirectory()
        let id = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let store = FileSyncCatchStore(directoryURL: directory.url)

        let absent = try await store.localModificationDate(id: id)
        XCTAssertNil(absent)

        try await store.importCatch(makeCatch(id: id), photoData: nil)
        let present = try await store.localModificationDate(id: id)
        XCTAssertNotNil(present)
    }
}