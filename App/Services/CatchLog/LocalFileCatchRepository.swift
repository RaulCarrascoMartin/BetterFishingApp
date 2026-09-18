import Foundation
import os

final class LocalFileCatchRepository: CatchRepository, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.betterfishing.BetterFishing", category: "LocalFileCatchRepository")

    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.directoryURL = applicationSupport.appendingPathComponent("Catches", isDirectory: true)
        }
    }

    func saveCatch(species: Species, photoData: Data, date: Date, location: LocationCoordinate2D?, notes: String) async throws -> Catch {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let id = UUID()
            let photoFilename = "\(id.uuidString).jpg"
            let catchEntry = Catch(
                id: id,
                species: species,
                photoPath: photoFilename,
                date: date,
                location: location,
                notes: notes,
                createdAt: Date()
            )

            let photoURL = directoryURL.appendingPathComponent(photoFilename)
            let jsonURL = directoryURL.appendingPathComponent("\(id.uuidString).json")

            try photoData.write(to: photoURL, options: .atomic)
            try JSONEncoder().encode(catchEntry).write(to: jsonURL, options: .atomic)
            Self.logger.info("Catch guardado: \(id.uuidString, privacy: .public)")
            return catchEntry
        } catch {
            Self.logger.error("Fallo al guardar catch: \(error.localizedDescription, privacy: .public)")
            throw CatchSaveError.writeFailed
        }
    }

    func listCatches() async throws -> [Catch] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Catch.self, from: data)
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    func getCatch(id: UUID) async throws -> Catch? {
        let jsonURL = directoryURL.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: jsonURL) else { return nil }
        return try? JSONDecoder().decode(Catch.self, from: data)
    }

    func updateCatch(id: UUID, date: Date?, location: LocationCoordinate2D?, notes: String?) async throws {
        do {
            let jsonURL = directoryURL.appendingPathComponent("\(id.uuidString).json")
            guard let data = try? Data(contentsOf: jsonURL),
                  var catchEntry = try? JSONDecoder().decode(Catch.self, from: data) else {
                return
            }
            if let date {
                catchEntry.date = date
            }
            catchEntry.location = location
            if let notes {
                catchEntry.notes = notes
            }
            try JSONEncoder().encode(catchEntry).write(to: jsonURL, options: .atomic)
            Self.logger.info("Catch actualizado: \(id.uuidString, privacy: .public)")
        } catch {
            Self.logger.error("Fallo al actualizar catch: \(error.localizedDescription, privacy: .public)")
            throw CatchSaveError.writeFailed
        }
    }

    func deleteCatch(id: UUID) async throws {
        do {
            let photoURL = directoryURL.appendingPathComponent("\(id.uuidString).jpg")
            let jsonURL = directoryURL.appendingPathComponent("\(id.uuidString).json")

            if FileManager.default.fileExists(atPath: photoURL.path) {
                try FileManager.default.removeItem(at: photoURL)
            }
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                try FileManager.default.removeItem(at: jsonURL)
            }
            Self.logger.info("Catch eliminado: \(id.uuidString, privacy: .public)")
        } catch {
            Self.logger.error("Fallo al eliminar catch: \(error.localizedDescription, privacy: .public)")
            throw CatchSaveError.writeFailed
        }
    }

    func photoData(for `catch`: Catch) -> Data? {
        let photoURL = directoryURL.appendingPathComponent(`catch`.photoPath)
        guard let data = try? Data(contentsOf: photoURL) else { return nil }
        return data
    }
}