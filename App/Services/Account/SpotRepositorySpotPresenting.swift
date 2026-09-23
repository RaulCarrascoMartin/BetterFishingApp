import Foundation

struct SpotRepositorySpotPresenting: FavoritesPresenting, Sendable {
    private let repository: any SpotRepository

    init(repository: any SpotRepository) {
        self.repository = repository
    }

    func favoriteSpotIDs() async throws -> Set<UUID> {
        do {
            return try await repository.favoriteSpotIDs()
        } catch let error as SpotRepositoryError {
            throw Self.translate(error, operation: .load)
        }
    }

    func favorites() async throws -> [FavoriteSpot] {
        do {
            return try await repository.favoriteSpots().map {
                FavoriteSpot(spotID: $0.id, name: $0.name, category: $0.category.rawValue)
            }
        } catch let error as SpotRepositoryError {
            throw Self.translate(error, operation: .load)
        }
    }

    func isFavorite(spotID: UUID) async throws -> Bool {
        try await favoriteSpotIDs().contains(spotID)
    }

    func setFavorite(spotID: UUID, isFavorite: Bool) async throws {
        do {
            try await repository.setFavorite(spotID: spotID, isFavorite: isFavorite)
        } catch let error as SpotRepositoryError {
            throw Self.translate(error, operation: isFavorite ? .save : .remove)
        }
    }

    private enum OperationKind {
        case load
        case save
        case remove
    }

    private static func translate(_ error: SpotRepositoryError, operation: OperationKind) -> FavoritesError {
        switch error {
        case .authenticationRequired:
            return .authenticationRequired
        default:
            switch operation {
            case .load:
                return .loadFailed(Self.reasonText(for: error))
            case .save:
                return .saveFailed(Self.reasonText(for: error))
            case .remove:
                return .removeFailed(Self.reasonText(for: error))
            }
        }
    }

    private static func reasonText(for error: SpotRepositoryError) -> String {
        switch error {
        case .queryFailed(let message):
            return message
        case .backendUnavailable:
            return "El servidor de spots no está disponible."
        case .authenticationRequired:
            return "Se requiere iniciar sesión."
        }
    }
}