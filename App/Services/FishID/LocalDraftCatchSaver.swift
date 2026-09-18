import Foundation
import os

enum CatchSaveError: Error, Equatable {
    case writeFailed
}

struct LocalDraftCatchSaver: CatchSaving {
    private static let logger = Logger(subsystem: "com.betterfishing.BetterFishing", category: "LocalDraftCatchSaver")

    private let draftsDirectory: URL

    init(draftsDirectory: URL? = nil) {
        if let draftsDirectory {
            self.draftsDirectory = draftsDirectory
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.draftsDirectory = applicationSupport.appendingPathComponent("ProvisionalDrafts", isDirectory: true)
        }
    }

    func saveDraft(species: Species, photoData: Data) async throws {
        do {
            try FileManager.default.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)

            let uuid = UUID()
            let photoFilename = "\(uuid.uuidString).jpg"
            let draft = CatchDraft(
                id: uuid,
                species: species,
                photoPath: photoFilename,
                createdAt: Date(),
                status: .draft
            )

            let photoURL = draftsDirectory.appendingPathComponent(photoFilename)
            let jsonURL = draftsDirectory.appendingPathComponent("\(uuid.uuidString).json")

            try photoData.write(to: photoURL, options: .atomic)
            try JSONEncoder().encode(draft).write(to: jsonURL, options: .atomic)
        } catch {
            Self.logger.error("Fallo al guardar draft local: \(error.localizedDescription, privacy: .public)")
            throw CatchSaveError.writeFailed
        }
    }
}