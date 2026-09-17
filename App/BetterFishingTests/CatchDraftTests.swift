import XCTest

@testable import BetterFishing

final class CatchDraftTests: XCTestCase {
    private let referenceTime: TimeInterval = 700_000_000

    private func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides",
            localizedName: "Lubina americana",
            referenceImageURL: URL(string: "https://fishial.example/species/largemouth.jpg")
        )
    }

    private func makeDraft() -> CatchDraft {
        CatchDraft(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            species: makeSpecies(),
            photoPath: "11111111-1111-1111-1111-111111111111.jpg",
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime),
            status: .draft
        )
    }

    func testCatchDraftRoundTripPreservesAllFields() throws {
        let draft = makeDraft()

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(CatchDraft.self, from: data)

        XCTAssertEqual(decoded.id, draft.id)
        XCTAssertEqual(decoded.species, draft.species)
        XCTAssertEqual(decoded.photoPath, draft.photoPath)
        XCTAssertEqual(decoded.createdAt, draft.createdAt)
        XCTAssertEqual(decoded.status, draft.status)
    }

    func testCatchDraftRoundTripPreservesEmbeddedSpeciesFully() throws {
        let draft = makeDraft()

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(CatchDraft.self, from: data)

        XCTAssertEqual(decoded.species.id, "species-largemouth")
        XCTAssertEqual(decoded.species.commonName, "Largemouth Bass")
        XCTAssertEqual(decoded.species.scientificName, "Micropterus salmoides")
        XCTAssertEqual(decoded.species.localizedName, "Lubina americana")
        XCTAssertEqual(
            decoded.species.referenceImageURL,
            URL(string: "https://fishial.example/species/largemouth.jpg")
        )
    }

    func testCatchDraftDecodesFromFixedJSON() throws {
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "species": {
                "id": "species-snook",
                "commonName": "Common Snook",
                "scientificName": "Centropomus undecimalis",
                "localizedName": "Róbalo",
                "referenceImageURL": "https://fishial.example/species/snook.jpg"
            },
            "photoPath": "22222222-2222-2222-2222-222222222222.jpg",
            "createdAt": 700000000,
            "status": "draft"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CatchDraft.self, from: json)

        XCTAssertEqual(decoded.id, UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        XCTAssertEqual(decoded.species.id, "species-snook")
        XCTAssertEqual(decoded.species.commonName, "Common Snook")
        XCTAssertEqual(decoded.species.scientificName, "Centropomus undecimalis")
        XCTAssertEqual(decoded.species.localizedName, "Róbalo")
        XCTAssertEqual(
            decoded.species.referenceImageURL,
            URL(string: "https://fishial.example/species/snook.jpg")
        )
        XCTAssertEqual(decoded.photoPath, "22222222-2222-2222-2222-222222222222.jpg")
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSinceReferenceDate: 700_000_000))
        XCTAssertEqual(decoded.status, .draft)
    }

    func testCatchDraftPropertiesAreAccessible() {
        let draft = makeDraft()

        XCTAssertEqual(draft.id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(draft.species.id, "species-largemouth")
        XCTAssertEqual(draft.photoPath, "11111111-1111-1111-1111-111111111111.jpg")
        XCTAssertEqual(draft.createdAt.timeIntervalSinceReferenceDate, referenceTime)
        XCTAssertEqual(draft.status, .draft)
    }

    func testCatchDraftStatusCodeEncodesAndDecodesToRawValue() throws {
        XCTAssertEqual(CatchDraftStatus.draft.rawValue, "draft")

        let data = try JSONEncoder().encode(CatchDraftStatus.draft)
        let decoded = try JSONDecoder().decode(CatchDraftStatus.self, from: data)

        XCTAssertEqual(decoded, .draft)
        XCTAssertEqual(decoded.rawValue, "draft")
    }
}