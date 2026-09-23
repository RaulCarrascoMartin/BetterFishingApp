import Foundation
import Supabase

actor SupabaseStorageService: SupabaseStoring {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func upload(
        bucket: String,
        path: String,
        data: Data,
        options: SupabaseUploadOptions?
    ) async throws -> String {
        do {
            let fileOptions = options.map {
                FileOptions(contentType: $0.contentType, upsert: $0.upsert)
            } ?? FileOptions()
            let response = try await client.storage.from(bucket).upload(
                path,
                data: data,
                options: fileOptions
            )
            return response.fullPath
        } catch let error as SupabaseBaseError {
            throw error
        } catch {
            throw SupabaseBaseError.uploadFailed
        }
    }

    func download(bucket: String, path: String) async throws -> Data {
        do {
            return try await client.storage.from(bucket).download(path: path)
        } catch let error as SupabaseBaseError {
            throw error
        } catch {
            throw SupabaseBaseError.downloadFailed
        }
    }
}