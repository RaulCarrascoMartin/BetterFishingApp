import Foundation

protocol SupabaseStoring: Sendable {
    func upload(
        bucket: String,
        path: String,
        data: Data,
        options: SupabaseUploadOptions?
    ) async throws -> String
    func download(bucket: String, path: String) async throws -> Data
}

struct SupabaseUploadOptions: Equatable, Sendable {
    var contentType: String
    var upsert: Bool

    init(contentType: String = "application/octet-stream", upsert: Bool = false) {
        self.contentType = contentType
        self.upsert = upsert
    }
}
