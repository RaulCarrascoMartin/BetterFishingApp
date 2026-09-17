import XCTest
@testable import BetterFishing

final class SpeciesTests: XCTestCase {
    private func makeSpecies(
        id: String = "fishial-123",
        localizedName: String? = nil,
        referenceImageURL: URL? = nil
    ) -> Species {
        Species(
            id: id,
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides",
            localizedName: localizedName,
            referenceImageURL: referenceImageURL
        )
    }

    func testJSONDecodingWithoutOptionalFieldsDefaultsToNil() throws {
        let json = """
        {
            "id": "fishial-123",
            "commonName": "Largemouth Bass",
            "scientificName": "Micropterus salmoides"
        }
        """.data(using: .utf8)!

        let species = try JSONDecoder().decode(Species.self, from: json)

        XCTAssertEqual(species.id, "fishial-123")
        XCTAssertEqual(species.commonName, "Largemouth Bass")
        XCTAssertEqual(species.scientificName, "Micropterus salmoides")
        XCTAssertNil(species.localizedName)
        XCTAssertNil(species.referenceImageURL)
    }

    func testJSONDecodingIncludesOptionalFields() throws {
        let json = """
        {
            "id": "fishial-456",
            "commonName": "Spanish Mackerel",
            "scientificName": "Scomberomorus maculatus",
            "localizedName": "Sierra",
            "referenceImageURL": "https://fishial.example/species/456.jpg"
        }
        """.data(using: .utf8)!

        let species = try JSONDecoder().decode(Species.self, from: json)

        XCTAssertEqual(species.localizedName, "Sierra")
        XCTAssertEqual(species.referenceImageURL, URL(string: "https://fishial.example/species/456.jpg"))
    }

    func testJSONEncodingRoundTripPreservesValues() throws {
        let species = makeSpecies(
            localizedName: "Lubina",
            referenceImageURL: URL(string: "https://fishial.example/species/123.jpg")
        )

        let data = try JSONEncoder().encode(species)
        let decoded = try JSONDecoder().decode(Species.self, from: data)

        XCTAssertEqual(decoded, species)
    }

    func testEqualSpeciesWithSameFieldsAreEqual() {
        let a = makeSpecies(id: "fishial-1")
        let b = makeSpecies(id: "fishial-1")

        XCTAssertEqual(a, b)
    }

    func testSpeciesWithDifferentIDAreNotEqual() {
        let a = makeSpecies(id: "fishial-1")
        let b = makeSpecies(id: "fishial-2")

        XCTAssertNotEqual(a, b)
    }

    func testSpeciesIsHashableInSetAndDictionary() {
        let species = makeSpecies(id: "fishial-1")
        let other = makeSpecies(id: "fishial-2")

        let speciesSet: Set<Species> = [species, other, species]
        XCTAssertEqual(speciesSet.count, 2)
        XCTAssertTrue(speciesSet.contains(species))

        var bySpecies: [Species: String] = [species: "bass"]
        bySpecies[other] = "mackerel"
        XCTAssertEqual(bySpecies[species], "bass")
        XCTAssertEqual(bySpecies[other], "mackerel")
    }

    func testSpeciesIsIdentifiableWithMatchingID() {
        let species = makeSpecies(id: "fishial-1")

        let identities: [Species.ID: Species] = [species.id: species]
        XCTAssertEqual(identities[species.id]?.commonName, "Largemouth Bass")
    }
}