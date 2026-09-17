import Foundation

protocol CatchSaving: Sendable {
    func saveDraft(species: Species, photoData: Data) async throws
}