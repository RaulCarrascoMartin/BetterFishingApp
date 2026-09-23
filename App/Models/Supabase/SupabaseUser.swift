import Foundation

struct SupabaseUser: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let email: String?
    let createdAt: Date
}