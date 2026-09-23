import Foundation

enum AccountProfileError: Error, Sendable, LocalizedError {
    case loadFailed(String)
    case updateFailed(String)
    case uploadAvatarFailed(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .loadFailed(let reason):
            return "No se pudo cargar el perfil: \(reason)"
        case .updateFailed(let reason):
            return "No se pudo guardar el perfil: \(reason)"
        case .uploadAvatarFailed(let reason):
            return "No se pudo subir el avatar: \(reason)"
        case .notAuthenticated:
            return "Necesitas iniciar sesión para acceder a tu perfil."
        }
    }
}

protocol ProfileManaging: Sendable {
    func profile() async throws -> AccountProfile
    func updateDisplayName(_ name: String) async throws
    func updateAvatar(data: Data, contentType: String) async throws -> String
    func avatarData(avatarPath: String) async throws -> Data?
}