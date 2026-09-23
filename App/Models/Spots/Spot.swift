import Foundation

struct Spot: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let category: SpotCategory
    var summary: String
    let longitude: Double
    let latitude: Double
    var distanceMeters: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, category, summary, longitude, latitude
        case distanceMeters = "distance_m"
    }

    var coordinate: LocationCoordinate2D {
        LocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}