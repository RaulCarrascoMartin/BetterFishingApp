import Foundation

struct AccountProfile: Codable, Sendable, Equatable {
    let userID: UUID
    let displayName: String?
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case avatarPath = "avatar_path"
    }
}