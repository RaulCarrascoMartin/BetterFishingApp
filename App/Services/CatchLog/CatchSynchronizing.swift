import Foundation

struct CatchSyncResult: Sendable, Equatable {
    let pushed: Int
    let pulled: Int
    let skipped: Int
}

enum CatchSyncError: Error, Sendable, LocalizedError {
    case noSession
    case remoteLoadFailed(String)
    case pushFailed(String)
    case pullFailed(String)
    case ledgerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "No hay una sesión activa para sincronizar el registro."
        case .remoteLoadFailed(let message):
            return "No se pudieron cargar las capturas de la cuenta: \(message)"
        case .pushFailed(let message):
            return "No se pudieron subir las capturas a la cuenta: \(message)"
        case .pullFailed(let message):
            return "No se pudieron descargar las capturas de la cuenta: \(message)"
        case .ledgerFailed(let message):
            return "No se pudo actualizar el estado de sincronización: \(message)"
        }
    }
}

protocol CatchSynchronizing: Sendable {
    func sync(userID: UUID) async throws -> CatchSyncResult
}