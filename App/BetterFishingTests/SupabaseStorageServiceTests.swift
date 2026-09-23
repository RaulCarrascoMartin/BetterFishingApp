import XCTest
import Supabase
@testable import BetterFishing

final class SupabaseStorageServiceTests: XCTestCase {
    private let uploadURL =
        "https://project-ref.supabase.co/storage/v1/object/catches/2026/season/catch-1.jpg"
    private let downloadURL =
        "https://project-ref.supabase.co/storage/v1/object/spots-media/map/overlays/legend.png"
    private let missingObjectURL =
        "https://project-ref.supabase.co/storage/v1/object/missing-bucket/ghost/reports/fish.csv"
    private let failingUploadURL =
        "https://project-ref.supabase.co/storage/v1/object/catches/broken/ultrasonic-sonde.jpg"

    override func setUp() {
        super.setUp()
        HTTPStubRegistry.shared.reset()
    }

    func testUploadReturnsStoredPathForArbitraryBucketAndPath() async throws {
        HTTPStubRegistry.shared.register(
            .json(["Key": "catches/2026/season/catch-1.jpg", "Id": "6f1d2c3b-8f2e-4a11-9e2e-0a1b2c3d4e5f"]),
            for: uploadURL
        )

        let storage = try makeStorageService()

        let storedPath = try await storage.upload(
            bucket: "catches",
            path: "2026/season/catch-1.jpg",
            data: Data([0xFF, 0xD8, 0xFF]),
            options: SupabaseUploadOptions(contentType: "image/jpeg", upsert: true)
        )

        XCTAssertEqual(storedPath, "catches/2026/season/catch-1.jpg")
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: uploadURL), 1)
        let headers = HTTPStubRegistry.shared.requestHeaders(for: uploadURL).first ?? [:]
        let upsertHeader = headers.first { $0.key.lowercased() == "x-upsert" }?.value
        XCTAssertEqual(upsertHeader, "true")
    }

    func testDownloadReturnsDataForArbitraryBucketAndPath() async throws {
        let payload = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        HTTPStubRegistry.shared.register(
            HTTPStub(statusCode: 200, data: payload, headers: ["Content-Type": "image/png"]),
            for: downloadURL
        )

        let storage = try makeStorageService()

        let data = try await storage.download(
            bucket: "spots-media",
            path: "map/overlays/legend.png"
        )

        XCTAssertEqual(data, payload)
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: downloadURL), 1)
    }

    func testDownloadWithNotFoundResponseThrowsDownloadFailed() async throws {
        HTTPStubRegistry.shared.register(
            .json(
                ["statusCode": "404", "message": "Object not found", "error": "not_found"],
                statusCode: 404
            ),
            for: missingObjectURL
        )

        let storage = try makeStorageService()

        do {
            _ = try await storage.download(
                bucket: "missing-bucket",
                path: "ghost/reports/fish.csv"
            )
            XCTFail("Expected download to throw")
        } catch let error as SupabaseBaseError {
            XCTAssertEqual(error, .downloadFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testUploadWithServerErrorThrowsUploadFailed() async throws {
        HTTPStubRegistry.shared.register(
            .json(["statusCode": "500", "message": "Internal server error"], statusCode: 500),
            for: failingUploadURL
        )

        let storage = try makeStorageService()

        do {
            _ = try await storage.upload(
                bucket: "catches",
                path: "broken/ultrasonic-sonde.jpg",
                data: Data([0x01]),
                options: nil
            )
            XCTFail("Expected upload to throw")
        } catch let error as SupabaseBaseError {
            XCTAssertEqual(error, .uploadFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private func makeStorageService() throws -> SupabaseStorageService {
        let supabaseURL = try XCTUnwrap(URL(string: "https://project-ref.supabase.co"))
        let options = SupabaseClientOptions(
            auth: .init(storage: InMemoryAuthLocalStorage(), autoRefreshToken: false),
            global: .init(session: .mockSession())
        )
        let client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: "test-anon-key",
            options: options
        )
        return SupabaseStorageService(client: client)
    }
}
