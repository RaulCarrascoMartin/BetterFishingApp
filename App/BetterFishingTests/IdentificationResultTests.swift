import XCTest

@testable import BetterFishing

final class IdentificationResultTests: XCTestCase {
    private func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
    }

    func testIdentificationResultStoresSpeciesCertaintyAndConfidence() {
        let species = makeSpecies()
        let result = IdentificationResult(
            species: species,
            certainty: 0.87,
            confidence: .reliable
        )

        XCTAssertEqual(result.species, species)
        XCTAssertEqual(result.certainty, 0.87)
        XCTAssertEqual(result.confidence, .reliable)
    }

    func testIdentificationResultIsEquatableByValue() {
        let species = makeSpecies()
        let first = IdentificationResult(species: species, certainty: 0.87, confidence: .reliable)
        let second = IdentificationResult(species: species, certainty: 0.87, confidence: .reliable)
        let differentCertainty = IdentificationResult(
            species: species,
            certainty: 0.4,
            confidence: .low
        )

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, differentCertainty)
    }

    func testIdentificationConfidenceCasesAreAccessible() {
        let reliable: IdentificationConfidence = .reliable
        let low: IdentificationConfidence = .low

        XCTAssertEqual(reliable, .reliable)
        XCTAssertEqual(low, .low)
        XCTAssertNotEqual(reliable, low)
    }

    func testIdentifiedOutcomeCarriesResult() {
        let species = makeSpecies()
        let result = IdentificationResult(species: species, certainty: 0.6, confidence: .low)
        let outcome = IdentificationOutcome.identified(result)

        guard case .identified(let identified) = outcome else {
            return XCTFail("Se esperaba .identified pero se obtuvo \(outcome)")
        }
        XCTAssertEqual(identified.species, species)
        XCTAssertEqual(identified.certainty, 0.6)
        XCTAssertEqual(identified.confidence, .low)
    }

    func testNoMatchOutcomeCarriesNoResult() {
        let outcome = IdentificationOutcome.noMatch

        guard case .noMatch = outcome else {
            return XCTFail("Se esperaba .noMatch pero se obtuvo \(outcome)")
        }
    }

    func testOutcomesAreEquatable() {
        let species = makeSpecies()
        let first = IdentificationResult(species: species, certainty: 0.87, confidence: .reliable)
        let second = IdentificationResult(species: species, certainty: 0.87, confidence: .reliable)

        XCTAssertEqual(IdentificationOutcome.identified(first), .identified(second))
        XCTAssertEqual(IdentificationOutcome.noMatch, .noMatch)
        XCTAssertNotEqual(IdentificationOutcome.identified(first), .noMatch)
    }
}