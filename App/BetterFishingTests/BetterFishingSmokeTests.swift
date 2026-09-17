import XCTest
@testable import BetterFishing

final class BetterFishingSmokeTests: XCTestCase {
    func testAppModuleResolvesThroughTestableImport() {
        let appType: Any.Type = BetterFishingApp.self
        XCTAssertEqual(String(describing: appType), "BetterFishingApp")
    }

    func testMockURLSessionReturnsStubbedResponse() async throws {
        let url = URL(string: "https://api.betterfishing.test/recognize")!
        HTTPStubRegistry.shared.register(HTTPStub.json(["ok": true]), for: url.absoluteString)
        defer { HTTPStubRegistry.shared.reset() }

        let session = URLSession.mockSession()
        let (data, response) = try await session.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Bool])
        XCTAssertEqual(body["ok"], true)
    }

    func testMockURLSessionFailsWithStubbedTimeout() async throws {
        let url = URL(string: "https://api.betterfishing.test/timeout")!
        HTTPStubRegistry.shared.register(HTTPStub(error: URLError(.timedOut)), for: url.absoluteString)
        defer { HTTPStubRegistry.shared.reset() }

        let session = URLSession.mockSession()
        do {
            _ = try await session.data(from: url)
            XCTFail("Expected the request to fail with the stubbed timeout error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    func testTemporaryDirectoryHelperCreatesAndRemovesDirectory() throws {
        let directory = try makeTemporaryDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.url.path))
        let url = directory.url
        directory.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}