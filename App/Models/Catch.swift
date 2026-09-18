import Foundation

struct Catch: Codable, Identifiable, Sendable {
    let id: UUID
    let species: Species
    let photoPath: String
    var date: Date
    var location: LocationCoordinate2D?
    var notes: String
    let createdAt: Date
}

struct LocationCoordinate2D: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double
}