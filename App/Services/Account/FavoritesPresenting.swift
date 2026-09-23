import Foundation

enum FavoritesError: Error, Sendable, LocalizedError {
    case loadFailed(String)
    case saveFailed(String)
    case removeFailed(String)
    case notAuthenticated
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .loadFailed(let reason):
            return "No se pudieron cargar los favoritos: \(reason)"
        case .saveFailed(let reason):
            return "No se pudo guardar el favorito: \(reason)"
        case .removeFailed(let reason):
            return "No se pudo eliminar el favorito: \(reason)"
        case .notAuthenticated:
            return "Necesitas iniciar sesión para gestionar tus favoritos."
        case .authenticationRequired:
            return "Se requiere iniciar sesión para gestionar tus favoritos."
        }
    }
}

protocol FavoritesPresenting: Sendable {
    func favorites() async throws -> [FavoriteSpot]
    func favoriteSpotIDs() async throws -> Set<UUID>
    func isFavorite(spotID: UUID) async throws -> Bool
    func setFavorite(spotID: UUID, isFavorite: Bool) async throws
}