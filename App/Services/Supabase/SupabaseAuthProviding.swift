import Foundation

protocol SupabaseAuthProviding: Sendable {
    func signUp(email: String, password: String) async throws -> SupabaseSession
    func signIn(email: String, password: String) async throws -> SupabaseSession
    func signOut() async throws
    func currentUser() async -> SupabaseUser?
    func currentSession() async throws -> SupabaseSession?
    func stateChanges() -> AsyncStream<SupabaseAuthEvent>
}

enum SupabaseAuthEvent: Sendable {
    case signedIn(SupabaseSession)
    case sessionRestored(SupabaseSession)
    case signedOut
}