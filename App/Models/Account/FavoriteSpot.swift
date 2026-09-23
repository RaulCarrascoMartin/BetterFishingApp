import Foundation

struct FavoriteSpot: Codable, Sendable, Equatable, Identifiable {
    let spotID: UUID
    let name: String
    let category: String?
    var id: UUID { spotID }
}