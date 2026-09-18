import Foundation

enum CatchSaveError: Error, Equatable {
    case writeFailed
}

protocol CatchRepository: Sendable {
    func saveCatch(species: Species, photoData: Data, date: Date, location: LocationCoordinate2D?, notes: String) async throws -> Catch
    func listCatches() async throws -> [Catch]
    func getCatch(id: UUID) async throws -> Catch?
    func updateCatch(id: UUID, date: Date?, location: LocationCoordinate2D?, notes: String?) async throws
    func deleteCatch(id: UUID) async throws
}