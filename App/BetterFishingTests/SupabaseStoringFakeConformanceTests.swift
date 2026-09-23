import Foundation
import XCTest

@testable import BetterFishing

struct StorageTestDoubleError: Error, Equatable {
    let reason: String
}

struct RecordedUpload: Equatable {
    let bucket: String
    let path: String
    let data: Data
    let options: SupabaseUploadOptions?
}

final class UploadRecorderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [RecordedUpload] = []

    var uploads: [RecordedUpload] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func append(_ upload: RecordedUpload) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(upload)
    }
}

struct StorageTestDouble: SupabaseStoring, Sendable {
    enum Outcome: Sendable {
        case success(path: String)
        case failure
    }

    private let outcome: Outcome
    private let downloadedData: Data
    private let recorder: UploadRecorderBox

    init(
        outcome: Outcome,
        downloadedData: Data = Data([0x0A]),
        recorder: UploadRecorderBox = UploadRecorderBox()
    ) {
        self.outcome = outcome
        self.downloadedData = downloadedData
        self.recorder = recorder
    }

    var recordedUploads: [RecordedUpload] {
        recorder.uploads
    }

    func upload(
        bucket: String,
        path: String,
        data: Data,
        options: SupabaseUploadOptions?
    ) async throws -> String {
        recorder.append(
            RecordedUpload(bucket: bucket, path: path, data: data, options: options)
        )
        switch outcome {
        case .success(let configuredPath):
            return configuredPath
        case .failure:
            throw StorageTestDoubleError(reason: "upload failed")
        }
    }

    func download(bucket: String, path: String) async throws -> Data {
        downloadedData
    }
}

final class SupabaseStoringFakeConformanceTests: XCTestCase {
    func testStorageTestDoubleIsUsableAsAnySupabaseStoringAndRecordsUploads() async throws {
        let double = StorageTestDouble(outcome: .success(path: "catches/catch-1.jpg"))
        let store: any SupabaseStoring = double

        let path = try await store.upload(
            bucket: "catches",
            path: "catch-1.jpg",
            data: Data([0x01, 0x02]),
            options: SupabaseUploadOptions(contentType: "image/jpeg", upsert: true)
        )

        XCTAssertEqual(path, "catches/catch-1.jpg")
        let recorded = double.recordedUploads
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.bucket, "catches")
        XCTAssertEqual(recorded.first?.path, "catch-1.jpg")
        XCTAssertEqual(recorded.first?.data, Data([0x01, 0x02]))
        XCTAssertEqual(
            recorded.first?.options,
            SupabaseUploadOptions(contentType: "image/jpeg", upsert: true)
        )
    }

    func testStorageTestDoubleSuccessfulUploadReturnsConfiguredPath() async throws {
        let store: any SupabaseStoring = StorageTestDouble(
            outcome: .success(path: "avatars/user-1/avatar.jpg")
        )

        let path = try await store.upload(
            bucket: "avatars",
            path: "user-1/avatar.jpg",
            data: Data(),
            options: nil
        )

        XCTAssertEqual(path, "avatars/user-1/avatar.jpg")
    }

    func testStorageTestDoubleFailingUploadThrows() async {
        let store: any SupabaseStoring = StorageTestDouble(outcome: .failure)

        do {
            _ = try await store.upload(
                bucket: "catches",
                path: "catch-1.jpg",
                data: Data([0x01]),
                options: nil
            )
            XCTFail("Expected upload to throw")
        } catch let error as StorageTestDoubleError {
            XCTAssertEqual(error, StorageTestDoubleError(reason: "upload failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testStorageTestDoubleDownloadReturnsConfiguredData() async throws {
        let store: any SupabaseStoring = StorageTestDouble(
            outcome: .success(path: "catches/catch-1.jpg"),
            downloadedData: Data([0xDE, 0xAD])
        )

        let data = try await store.download(bucket: "catches", path: "catch-1.jpg")

        XCTAssertEqual(data, Data([0xDE, 0xAD]))
    }

    func testSupabaseUploadOptionsDefaultsMatchContract() {
        let options = SupabaseUploadOptions()

        XCTAssertEqual(options.contentType, "application/octet-stream")
        XCTAssertEqual(options.upsert, false)
        XCTAssertEqual(options, SupabaseUploadOptions(contentType: "application/octet-stream", upsert: false))
    }
}
