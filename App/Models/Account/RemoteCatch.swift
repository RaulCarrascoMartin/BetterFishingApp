import Foundation

struct RemoteCatch: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let userID: UUID
    let species: Species
    let date: Date
    let location: LocationCoordinate2D?
    let notes: String
    let createdAt: Date
    let updatedAt: Date
    let photoPath: String?

    enum CodingKeys: String, CodingKey {
        case id, species, date, location, notes, photoPath = "photo_path"
        case userID = "user_id", createdAt = "created_at", updatedAt = "updated_at"
    }

    func asCatch() async throws -> Catch {
        Catch(
            id: id,
            species: species,
            photoPath: photoPath ?? "\(id.uuidString).jpg",
            date: date,
            location: location,
            notes: notes,
            createdAt: createdAt
        )
    }
}