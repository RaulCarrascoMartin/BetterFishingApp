import CryptoKit
import Foundation

enum Fingerprint: Codable, Sendable, Equatable, Hashable {
    case sha256(String)

    static func of(_ catchEntry: Catch) -> Fingerprint {
        let payload = CatchFingerprintPayload(
            id: catchEntry.id,
            species: catchEntry.species,
            date: catchEntry.date,
            location: catchEntry.location,
            notes: catchEntry.notes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(payload)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return .sha256(hex)
    }
}

struct CatchFingerprintPayload: Codable, Sendable {
    let id: UUID
    let species: Species
    let date: Date
    let location: LocationCoordinate2D?
    let notes: String
}

struct CatchSyncLedgerEntry: Codable, Sendable, Equatable {
    var lastLocalFingerprint: Fingerprint?
    var lastRemoteUpdatedAt: Date?
    var lastLocalPushedAt: Date?
}

struct CatchSyncLedgerSnapshot: Codable, Sendable, Equatable {
    var entries: [UUID: CatchSyncLedgerEntry]
    var tombstonedIDs: Set<UUID>
    var lastSyncedRemoteIDs: Set<UUID>
}

actor CatchSyncLedger {
    private let fileURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.fileURL = directoryURL.appendingPathComponent("sync-ledger.json")
        self.fileManager = fileManager
    }

    func snapshot() async throws -> CatchSyncLedgerSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return CatchSyncLedgerSnapshot(
                entries: [:],
                tombstonedIDs: [],
                lastSyncedRemoteIDs: []
            )
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(CatchSyncLedgerSnapshot.self, from: data)
    }

    func commit(_ snapshot: CatchSyncLedgerSnapshot) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        let temporaryURL = directoryURL.appendingPathComponent("sync-ledger-\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: .atomic)
        _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
    }
}