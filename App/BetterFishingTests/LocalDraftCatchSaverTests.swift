import XCTest

@testable import BetterFishing

final class LocalDraftCatchSaverTests: XCTestCase {
    private let photoData = Data([0x0A, 0x0B, 0x0C, 0x0D])

    private func makeSpecies(localizedName: String? = nil) -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides",
            localizedName: localizedName
        )
    }

    func testSaveDraftWritesJPEGAndJSONAndAllowsReRead() async throws {
        let directory = try makeTemporaryDirectory()
        let saver = LocalDraftCatchSaver(draftsDirectory: directory.url)
        let species = makeSpecies(localizedName: "Lubina americana")

        try await saver.saveDraft(species: species, photoData: photoData)

        let files = try FileManager.default.contentsOfDirectory(
            at: directory.url,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 2)

        let jsonFile = try XCTUnwrap(files.first { $0.pathExtension == "json" })
        let jpegFile = try XCTUnwrap(files.first { $0.pathExtension == "jpg" })

        let draft = try JSONDecoder().decode(CatchDraft.self, from: Data(contentsOf: jsonFile))
        XCTAssertEqual(draft.species.id, "species-largemouth")
        XCTAssertEqual(draft.species.commonName, "Largemouth Bass")
        XCTAssertEqual(draft.species.scientificName, "Micropterus salmoides")
        XCTAssertEqual(draft.species.localizedName, "Lubina americana")
        XCTAssertEqual(draft.status, .draft)
        XCTAssertEqual(draft.photoPath, jpegFile.lastPathComponent)
        XCTAssertEqual(draft.photoPath, draft.id.uuidString + ".jpg")
        XCTAssertEqual((draft.photoPath as NSString).pathExtension, "jpg")

        let savedPhoto = try Data(contentsOf: jpegFile)
        XCTAssertEqual(savedPhoto, photoData)
    }

    func testSaveDraftPropagatesErrorWhenDirectoryCannotBeCreated() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("not-a-directory")
        try Data([0x00]).write(to: fileURL)
        let saver = LocalDraftCatchSaver(draftsDirectory: fileURL)

        do {
            try await saver.saveDraft(species: makeSpecies(), photoData: photoData)
            XCTFail("Se esperaba que saveDraft lanzase CatchSaveError")
        } catch let error as CatchSaveError {
            XCTAssertEqual(error, .writeFailed)
        } catch {
            XCTFail("Se esperaba CatchSaveError pero se obtuvo \(error)")
        }
    }

    func testSaveDraftWithSpeciesWithoutLocalizedName() async throws {
        let directory = try makeTemporaryDirectory()
        let saver = LocalDraftCatchSaver(draftsDirectory: directory.url)

        try await saver.saveDraft(species: makeSpecies(), photoData: photoData)

        let files = try FileManager.default.contentsOfDirectory(
            at: directory.url,
            includingPropertiesForKeys: nil
        )
        let jsonFile = try XCTUnwrap(files.first { $0.pathExtension == "json" })
        let draft = try JSONDecoder().decode(CatchDraft.self, from: Data(contentsOf: jsonFile))
        XCTAssertEqual(draft.species.localizedName, nil)
        XCTAssertEqual(draft.species.id, "species-largemouth")
    }

    func testSaveDraftIsConsumableAsCatchSaving() async throws {
        let directory = try makeTemporaryDirectory()
        let saver = LocalDraftCatchSaver(draftsDirectory: directory.url)
        let concrete: any CatchSaving = saver

        try await concrete.saveDraft(species: makeSpecies(), photoData: photoData)
    }
}