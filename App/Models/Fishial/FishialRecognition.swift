import Foundation

struct FishialRecognitionResponse: Decodable, Sendable {
    let ok: Bool
    let queryToken: String?
    let objects: [FishialObject]
    let definitions: [String: FishialSpeciesDefinition]
}

struct FishialObject: Decodable, Sendable {
    let bbox: [Double]?
    let shape: [Double]?
    let species: [FishialSpeciesCandidate]
}

struct FishialSpeciesCandidate: Decodable, Sendable {
    let id: String
    let certainty: Double
}

struct FishialSpeciesDefinition: Decodable, Sendable {
    let commonName: String
    let scientificName: String
    let imageUrl: String?
}