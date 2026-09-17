import Foundation

protocol FishIdentifying: Sendable {
    func recognize(imageData: Data) async throws -> IdentificationOutcome
}