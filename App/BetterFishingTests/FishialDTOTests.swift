import XCTest

@testable import BetterFishing

final class FishialDTOTests: XCTestCase {
    private func makeSnakeCaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    // MARK: - FishialTokenResponse

    func testTokenResponseDecodesSnakeCaseKeys() throws {
        let json = """
        {
            "token_type": "Bearer",
            "access_token": "jwt-token-123"
        }
        """.data(using: .utf8)!

        let response = try makeSnakeCaseDecoder().decode(FishialTokenResponse.self, from: json)

        XCTAssertEqual(response.tokenType, "Bearer")
        XCTAssertEqual(response.accessToken, "jwt-token-123")
    }

    func testTokenResponseDecodesAbsentTokenTypeAsNil() throws {
        let json = """
        {
            "access_token": "jwt-token-123"
        }
        """.data(using: .utf8)!

        let response = try makeSnakeCaseDecoder().decode(FishialTokenResponse.self, from: json)

        XCTAssertNil(response.tokenType)
        XCTAssertEqual(response.accessToken, "jwt-token-123")
    }

    // MARK: - FishialRecognitionResponse

    func testRecognitionResponseDecodesValidPayload() throws {
        let json = """
        {
            "ok": true,
            "query_token": "query-abc",
            "objects": [
                {
                    "bbox": [1.0, 2.0, 3.0, 4.0],
                    "shape": [5.0, 6.0],
                    "species": [
                        { "id": "species-largemouth", "certainty": 0.87 }
                    ]
                }
            ],
            "definitions": {
                "species-largemouth": {
                    "common_name": "Largemouth Bass",
                    "scientific_name": "Micropterus salmoides",
                    "image_url": "https://fishial.example/largemouth.jpg"
                }
            }
        }
        """.data(using: .utf8)!

        let response = try makeSnakeCaseDecoder().decode(FishialRecognitionResponse.self, from: json)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.queryToken, "query-abc")
        XCTAssertEqual(response.objects.count, 1)

        let object = try XCTUnwrap(response.objects.first)
        XCTAssertEqual(object.bbox, [1.0, 2.0, 3.0, 4.0])
        XCTAssertEqual(object.shape, [5.0, 6.0])
        XCTAssertEqual(object.species.count, 1)

        let candidate = try XCTUnwrap(object.species.first)
        XCTAssertEqual(candidate.id, "species-largemouth")
        XCTAssertEqual(candidate.certainty, 0.87)

        let definition = try XCTUnwrap(response.definitions["species-largemouth"])
        XCTAssertEqual(definition.commonName, "Largemouth Bass")
        XCTAssertEqual(definition.scientificName, "Micropterus salmoides")
        XCTAssertEqual(definition.imageUrl, "https://fishial.example/largemouth.jpg")
    }

    func testRecognitionResponseDecodesEmptyObjects() throws {
        let json = """
        {
            "ok": true,
            "query_token": "query-empty",
            "objects": [],
            "definitions": {}
        }
        """.data(using: .utf8)!

        let response = try makeSnakeCaseDecoder().decode(FishialRecognitionResponse.self, from: json)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.queryToken, "query-empty")
        XCTAssertTrue(response.objects.isEmpty)
        XCTAssertTrue(response.definitions.isEmpty)
    }

    func testRecognitionResponseDecodesDefinitionWithoutImageUrlAsNil() throws {
        let json = """
        {
            "ok": true,
            "objects": [
                {
                    "species": [
                        { "id": "species-bass", "certainty": 0.6 }
                    ]
                }
            ],
            "definitions": {
                "species-bass": {
                    "common_name": "Largemouth Bass",
                    "scientific_name": "Micropterus salmoides"
                }
            }
        }
        """.data(using: .utf8)!

        let response = try makeSnakeCaseDecoder().decode(FishialRecognitionResponse.self, from: json)

        let object = try XCTUnwrap(response.objects.first)
        XCTAssertNil(object.bbox)
        XCTAssertNil(object.shape)

        let definition = try XCTUnwrap(response.definitions["species-bass"])
        XCTAssertEqual(definition.commonName, "Largemouth Bass")
        XCTAssertEqual(definition.scientificName, "Micropterus salmoides")
        XCTAssertNil(definition.imageUrl)
    }

    func testRecognitionResponseFailsWhenDefinitionMissingRequiredNames() throws {
        let json = """
        {
            "ok": true,
            "objects": [],
            "definitions": {
                "species-bass": {
                    "image_url": "https://fishial.example/bass.jpg"
                }
            }
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(
            try makeSnakeCaseDecoder().decode(FishialRecognitionResponse.self, from: json)
        )
    }
}