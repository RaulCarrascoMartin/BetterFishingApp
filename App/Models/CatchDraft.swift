import Foundation

enum CatchDraftStatus: String, Codable, Sendable {
    case draft
}

struct CatchDraft: Codable, Sendable {
    let id: UUID
    let species: Species
    let photoPath: String
    let createdAt: Date
    let status: CatchDraftStatus
}