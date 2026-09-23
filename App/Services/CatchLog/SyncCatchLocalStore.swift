import Foundation

protocol SyncCatchLocalStore: Sendable {
    func importCatch(_ entry: Catch, photoData: Data?) async throws
    func localCatch(id: UUID) async throws -> Catch?
    func localModificationDate(id: UUID) async throws -> Date?
    func photoData(for id: UUID) async -> Data?
}