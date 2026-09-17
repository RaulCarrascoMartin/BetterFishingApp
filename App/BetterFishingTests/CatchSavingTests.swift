import XCTest

@testable import BetterFishing

final class CatchSavingTests: XCTestCase {
    private let photoData = Data([0x0A, 0x0B, 0x0C])

    private func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
    }

    func testSaveDraftSuccessDoesNotThrowAndRecordsInputs() async throws {
        let fake = CatchSavingFake()
        let species = makeSpecies()
        fake.stubResult = .success(())

        try await fake.saveDraft(species: species, photoData: photoData)

        XCTAssertEqual(fake.receivedSpecies.count, 1)
        XCTAssertEqual(fake.receivedSpecies.first, species)
        XCTAssertEqual(fake.receivedPhotoData.count, 1)
        XCTAssertEqual(fake.receivedPhotoData.first, photoData)
    }

    func testSaveDraftPropagatesProgrammedError() async {
        let fake = CatchSavingFake()
        fake.stubResult = .failure(CatchSavingFakeError.saveFailed)

        do {
            try await fake.saveDraft(species: makeSpecies(), photoData: photoData)
            XCTFail("Se esperaba que saveDraft lanzase el error programado")
        } catch {
            XCTAssertEqual(error as? CatchSavingFakeError, .saveFailed)
        }
    }

    func testCatchSavingFakeIsConsumableAsCatchSaving() async throws {
        let concreteFake = CatchSavingFake()
        concreteFake.stubResult = .success(())
        let saver: any CatchSaving = concreteFake

        try await saver.saveDraft(species: makeSpecies(), photoData: photoData)
    }
}