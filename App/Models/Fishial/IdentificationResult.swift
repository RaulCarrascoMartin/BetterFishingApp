import Foundation

struct IdentificationResult: Equatable, Sendable {
    let species: Species
    let certainty: Double
    let confidence: IdentificationConfidence
}

enum IdentificationConfidence: Equatable, Sendable {
    case reliable
    case low
}

enum IdentificationOutcome: Equatable, Sendable {
    case identified(IdentificationResult)
    case noMatch
}