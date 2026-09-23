import Foundation

enum AccountSessionState: Sendable, Equatable {
    case signedOut
    case signedIn(SupabaseUser)
}

enum AccountError: Error, Sendable, LocalizedError {
    case signUpFailed(String)
    case signInFailed(String)
    case signOutFailed(String)
    case sessionUnavailable

    var errorDescription: String? {
        switch self {
        case .signUpFailed(let reason):
            return "No se pudo crear la cuenta: \(reason)"
        case .signInFailed(let reason):
            return "No se pudo iniciar sesión: \(reason)"
        case .signOutFailed(let reason):
            return "No se pudo cerrar la sesión: \(reason)"
        case .sessionUnavailable:
            return "No hay una sesión de cuenta disponible."
        }
    }
}

protocol AccountSessionManaging: Sendable {
    var currentUser: SupabaseUser? { get async }
    var sessionState: AsyncStream<AccountSessionState> { get }
    func signUp(email: String, password: String) async throws
    func signIn(email: String, password: String) async throws
    func signOut() async throws
}