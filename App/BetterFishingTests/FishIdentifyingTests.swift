import XCTest

@testable import BetterFishing

final class FishIdentifyingTests: XCTestCase {
    private let imageData = Data([0x01, 0x02, 0x03])

    private func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
    }

    func testRecognizeReturnsIdentifiedOutcomeWhenProgrammed() async throws {
        let fake = FishIdentifyingFake()
        let species = makeSpecies()
        let expected = IdentificationOutcome.identified(
            IdentificationResult(species: species, certainty: 0.87, confidence: .reliable)
        )
        fake.stubResult = .success(expected)

        let outcome = try await fake.recognize(imageData: imageData)

        XCTAssertEqual(outcome, expected)
    }

    func testRecognizeReturnsNoMatchWhenProgrammed() async throws {
        let fake = FishIdentifyingFake()
        fake.stubResult = .success(.noMatch)

        let outcome = try await fake.recognize(imageData: imageData)

        XCTAssertEqual(outcome, .noMatch)
    }

    func testRecognizePropagatesProgrammedErrorAsThrow() async {
        let fake = FishIdentifyingFake()
        fake.stubResult = .failure(FakeRecognitionError.recognitionFailed)

        do {
            _ = try await fake.recognize(imageData: imageData)
            XCTFail("Se esperaba que recognize lanzase el error programado")
        } catch {
            XCTAssertEqual(error as? FakeRecognitionError, .recognitionFailed)
        }
    }

    func testRecognizeRecordsReceivedImageData() async throws {
        let fake = FishIdentifyingFake()
        fake.stubResult = .success(.noMatch)

        _ = try await fake.recognize(imageData: imageData)

        XCTAssertEqual(fake.receivedImageData.count, 1)
        XCTAssertEqual(fake.receivedImageData.first, imageData)
    }
}

private enum FakeRecognitionError: Error, Equatable {
    case recognitionFailed
}