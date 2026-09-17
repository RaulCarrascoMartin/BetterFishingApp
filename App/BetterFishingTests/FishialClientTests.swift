import Foundation
import XCTest

@testable import BetterFishing

final class FishialClientTests: XCTestCase {
    private let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

    private var recognizeURL: URL { FishialConfiguration.recognizeEndpoint }
    private var authURL: URL { FishialConfiguration.authEndpoint }

    override func setUp() {
        super.setUp()
        HTTPStubRegistry.shared.reset()
    }

    override func tearDown() {
        HTTPStubRegistry.shared.reset()
        super.tearDown()
    }

    // MARK: - Éxito y clasificación

    func testRecognizeReturnsReliableIdentifiedOutcomeOnSuccess() async throws {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            recognizeJSON(
                objects: [fishObject(species: [["id": "species-largemouth", "certainty": 0.87]])],
                definitions: [
                    "species-largemouth": definition(
                        commonName: "Largemouth Bass",
                        scientificName: "Micropterus salmoides",
                        imageURL: "https://fishial.example/largemouth.jpg"
                    )
                ]
            ),
            for: recognizeURL.absoluteString
        )

        let outcome = try await makeClient().recognize(imageData: imageData)

        guard case let .identified(result) = outcome else {
            XCTFail("Se esperaba .identified, recibí \(outcome)")
            return
        }
        XCTAssertEqual(
            result.species,
            Species(
                id: "species-largemouth",
                commonName: "Largemouth Bass",
                scientificName: "Micropterus salmoides",
                localizedName: nil,
                referenceImageURL: URL(string: "https://fishial.example/largemouth.jpg")
            )
        )
        XCTAssertEqual(result.certainty, 0.87)
        XCTAssertEqual(result.confidence, .reliable)
    }

    func testRecognizeSendsImageBodyWithAuthAndJPEGHeaders() async throws {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            recognizeJSON(
                objects: [fishObject(species: [["id": "species-largemouth", "certainty": 0.87]])],
                definitions: [
                    "species-largemouth": definition(
                        commonName: "Largemouth Bass",
                        scientificName: "Micropterus salmoides"
                    )
                ]
            ),
            for: recognizeURL.absoluteString
        )

        _ = try await makeClient().recognize(imageData: imageData)

        let headers = try XCTUnwrap(
            HTTPStubRegistry.shared.requestHeaders(for: recognizeURL.absoluteString).first
        )
        XCTAssertEqual(headers["Authorization"], "Bearer jwt-token-1")
        XCTAssertEqual(headers["Content-Type"], "image/jpeg")

        let body = try XCTUnwrap(
            HTTPStubRegistry.shared.requestBodies(for: recognizeURL.absoluteString).first
        )
        XCTAssertEqual(body, imageData)
    }

    func testRecognizeSelectsFirstCandidateOfFirstObject() async throws {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            recognizeJSON(
                objects: [
                    fishObject(species: [
                        ["id": "species-first", "certainty": 0.6],
                        ["id": "species-second", "certainty": 0.9]
                    ]),
                    fishObject(species: [["id": "species-other", "certainty": 0.99]])
                ],
                definitions: [
                    "species-first": definition(
                        commonName: "First Fish",
                        scientificName: "Firstus fishus"
                    ),
                    "species-second": definition(
                        commonName: "Second Fish",
                        scientificName: "Secondus fishus"
                    ),
                    "species-other": definition(
                        commonName: "Other Fish",
                        scientificName: "Otherus fishus"
                    )
                ]
            ),
            for: recognizeURL.absoluteString
        )

        let outcome = try await makeClient().recognize(imageData: imageData)

        guard case let .identified(result) = outcome else {
            XCTFail("Se esperaba .identified, recibí \(outcome)")
            return
        }
        XCTAssertEqual(result.species.id, "species-first")
    }

    func testRecognizeMarksLowConfidenceWhenCertaintyIsBelowReliableThreshold() async throws {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            recognizeJSON(
                objects: [fishObject(species: [["id": "species-bass", "certainty": 0.4]])],
                definitions: [
                    "species-bass": definition(
                        commonName: "Largemouth Bass",
                        scientificName: "Micropterus salmoides"
                    )
                ]
            ),
            for: recognizeURL.absoluteString
        )

        let outcome = try await makeClient().recognize(imageData: imageData)

        guard case let .identified(result) = outcome else {
            XCTFail("Se esperaba .identified, recibí \(outcome)")
            return
        }
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.certainty, 0.4)
        XCTAssertNil(result.species.localizedName)
        XCTAssertNil(result.species.referenceImageURL)
    }

    func testRecognizeReturnsNoMatchWhenCertaintyIsBelowLowThreshold() async throws {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            recognizeJSON(
                objects: [fishObject(species: [["id": "species-bass", "certainty": 0.29]])],
                definitions: [
                    "species-bass": definition(
                        commonName: "Largemouth Bass",
                        scientificName: "Micropterus salmoides"
                    )
                ]
            ),
            for: recognizeURL.absoluteString
        )

        let outcome = try await makeClient().recognize(imageData: imageData)

        XCTAssertEqual(outcome, .noMatch)
    }

    func testRecognizeReturnsNoMatchWhenObjectsAreEmpty() async throws {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            recognizeJSON(objects: [], definitions: [:]),
            for: recognizeURL.absoluteString
        )

        let outcome = try await makeClient().recognize(imageData: imageData)

        XCTAssertEqual(outcome, .noMatch)
    }

    // MARK: - Reintento 401

    func testRecognizeRetriesOnceAfter401RenewingToken() async throws {
        HTTPStubRegistry.shared.enqueue(
            [
                HTTPStub.json(["token_type": "Bearer", "access_token": "jwt-token-1"]),
                HTTPStub.json(["token_type": "Bearer", "access_token": "jwt-token-2"])
            ],
            for: authURL.absoluteString
        )
        HTTPStubRegistry.shared.enqueue(
            [
                HTTPStub(
                    statusCode: 401,
                    data: Data(#"{"errors":["auth_token_expired"]}"#.utf8)
                ),
                recognizeJSON(
                    objects: [fishObject(species: [["id": "species-bass", "certainty": 0.9]])],
                    definitions: [
                        "species-bass": definition(
                            commonName: "Largemouth Bass",
                            scientificName: "Micropterus salmoides"
                        )
                    ]
                )
            ],
            for: recognizeURL.absoluteString
        )

        let outcome = try await makeClient().recognize(imageData: imageData)

        guard case .identified = outcome else {
            XCTFail("Se esperaba .identified tras el reintento, recibí \(outcome)")
            return
        }
        XCTAssertEqual(
            HTTPStubRegistry.shared.requestCount(for: authURL.absoluteString),
            2,
            "El TokenStore debe renovar el token tras el 401"
        )
        let headers = HTTPStubRegistry.shared.requestHeaders(for: recognizeURL.absoluteString)
        XCTAssertEqual(headers.count, 2, "recognize debe ejecutarse dos veces")
        let firstCall = try XCTUnwrap(headers.first)
        XCTAssertEqual(firstCall["Authorization"], "Bearer jwt-token-1")
        let secondCall = try XCTUnwrap(headers.dropFirst().first)
        XCTAssertEqual(secondCall["Authorization"], "Bearer jwt-token-2")
    }

    func testRecognizeThrowsUnauthorizedWhenRetryStillReturns401() async throws {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            HTTPStub(statusCode: 401, data: Data(#"{"errors":["auth_token_expired"]}"#.utf8)),
            for: recognizeURL.absoluteString
        )

        do {
            _ = try await makeClient().recognize(imageData: imageData)
            XCTFail("Se esperaba FishialClientError.unauthorized si el 401 persiste")
        } catch let error as FishialClientError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: recognizeURL.absoluteString), 2)
    }

    // MARK: - Errores HTTP y respuestas no JSON

    func testRecognizeThrowsServerErrorForUnsupportedStatusCodes() async throws {
        for statusCode in [413, 415, 422] {
            HTTPStubRegistry.shared.reset()
            registerAuthStub(token: "jwt-token-1")
            HTTPStubRegistry.shared.register(
                HTTPStub(statusCode: statusCode),
                for: recognizeURL.absoluteString
            )

            do {
                _ = try await makeClient().recognize(imageData: imageData)
                XCTFail("Se esperaba error para HTTP \(statusCode)")
            } catch let error as FishialClientError {
                XCTAssertEqual(error, .serverError(statusCode: statusCode))
            } catch {
                XCTFail("Error inesperado para HTTP \(statusCode): \(error)")
            }
        }
    }

    func testRecognizeThrowsInvalidResponseForHTMLBody() async throws {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            HTTPStub(
                statusCode: 200,
                data: Data("<html><body>Bad Gateway</body></html>".utf8),
                headers: ["Content-Type": "text/html"]
            ),
            for: recognizeURL.absoluteString
        )

        do {
            _ = try await makeClient().recognize(imageData: imageData)
            XCTFail("Se esperaba FishialClientError.invalidResponse ante HTML")
        } catch let error as FishialClientError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func testRecognizeThrowsInvalidResponseForPlainTextBody() async throws {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            HTTPStub(
                statusCode: 200,
                data: Data("some plain text".utf8),
                headers: ["Content-Type": "text/plain"]
            ),
            for: recognizeURL.absoluteString
        )

        do {
            _ = try await makeClient().recognize(imageData: imageData)
            XCTFail("Se esperaba FishialClientError.invalidResponse ante texto plano")
        } catch let error as FishialClientError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func testRecognizeThrowsInvalidResponseWhenOKIsFalse() async throws {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            recognizeJSON(objects: [], definitions: [:], ok: false),
            for: recognizeURL.absoluteString
        )

        do {
            _ = try await makeClient().recognize(imageData: imageData)
            XCTFail("Se esperaba FishialClientError.invalidResponse ante ok: false")
        } catch let error as FishialClientError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    // MARK: - Timeout

    func testRecognizePropagatesTimeoutError() async {
        registerAuthStub(token: "jwt-token-1")
        HTTPStubRegistry.shared.register(
            HTTPStub(error: URLError(.timedOut)),
            for: recognizeURL.absoluteString
        )

        do {
            _ = try await makeClient().recognize(imageData: imageData)
            XCTFail("Se esperaba que recognize propagase el timeout")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeClient() -> FishialClient {
        let session = URLSession.mockSession()
        let store = FishialTokenStore(
            clientID: "test-client-id",
            clientSecret: "test-client-secret",
            session: session
        )
        return FishialClient(session: session, tokenStore: store)
    }

    private func registerAuthStub(token: String) {
        HTTPStubRegistry.shared.register(
            HTTPStub.json(["token_type": "Bearer", "access_token": token]),
            for: authURL.absoluteString
        )
    }

    private func recognizeJSON(
        objects: [[String: Any]] = [],
        definitions: [String: [String: String]] = [:],
        ok: Bool = true
    ) -> HTTPStub {
        let payload: [String: Any] = [
            "ok": ok,
            "query_token": "query-test",
            "objects": objects,
            "definitions": definitions
        ]
        return HTTPStub.json(payload)
    }

    private func fishObject(
        species: [[String: Any]],
        bbox: [Double] = [1.0, 2.0, 3.0, 4.0],
        shape: [Double] = [5.0, 6.0]
    ) -> [String: Any] {
        ["bbox": bbox, "shape": shape, "species": species]
    }

    private func definition(
        commonName: String,
        scientificName: String,
        imageURL: String? = nil
    ) -> [String: String] {
        var definition: [String: String] = [
            "common_name": commonName,
            "scientific_name": scientificName
        ]
        if let imageURL {
            definition["image_url"] = imageURL
        }
        return definition
    }
}