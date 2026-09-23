import Foundation
import os

enum SyncCatchStoreError: Error, Equatable, Sendable {
    case writeFailed
}

actor FileSyncCatchStore: SyncCatchLocalStore {
    private static let logger = Logger(subsystem: "com.betterfishing.BetterFishing", category: "CatchSync")

    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func importCatch(_ entry: Catch, photoData: Data?) async throws {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let jsonURL = directoryURL.appendingPathComponent("\(entry.id.uuidString).json")
            try JSONEncoder().encode(entry).write(to: jsonURL, options: .atomic)
            if let photoData {
                let photoURL = directoryURL.appendingPathComponent("\(entry.id.uuidString).jpg")
                try photoData.write(to: photoURL, options: .atomic)
            }
            Self.logger.info("Catch descargado e importado: \(entry.id.uuidString, privacy: .public)")
        } catch {
            Self.logger.error("Fallo al importar catch: \(error.localizedDescription, privacy: .public)")
            throw SyncCatchStoreError.writeFailed
        }
    }

    func localCatch(id: UUID) async throws -> Catch? {
        let jsonURL = directoryURL.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: jsonURL) else { return nil }
        return try? JSONDecoder().decode(Catch.self, from: data)
    }

    func localModificationDate(id: UUID) async throws -> Date? {
        let jsonURL = directoryURL.appendingPathComponent("\(id.uuidString).json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: jsonURL.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    func photoData(for id: UUID) async -> Data? {
        let photoURL = directoryURL.appendingPathComponent("\(id.uuidString).jpg")
        return try? Data(contentsOf: photoURL)
    }
}