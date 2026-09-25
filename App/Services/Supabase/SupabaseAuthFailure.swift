import Foundation

enum SupabaseAuthFailureReason: String, Sendable, Equatable {
    case invalidCredentials
    case emailNotConfirmed
    case network
    case configuration
    case server
    case unknown
}

struct SupabaseAuthFailure: Sendable, Equatable {
    let reason: SupabaseAuthFailureReason
    let description: String
}