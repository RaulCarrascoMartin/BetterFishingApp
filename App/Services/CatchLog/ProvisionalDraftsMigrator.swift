import Foundation
import os

struct ProvisionalDraftsMigrator: Sendable {
    private static let logger = Logger(
        subsystem: "com.betterfishing.BetterFishing",
        category: "ProvisionalDraftsMigrator"
    )

    private let catchRepository: any CatchRepository
    private let draftsDirectory: URL

    init(catchRepository: any CatchRepository, draftsDirectory: URL? = nil) {
        self.catchRepository = catchRepository
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

    func migrateIfNeeded() async throws {
        let fileManager = FileManager.default
        let markerURL = draftsDirectory.appendingPathComponent(".migrated")

        guard fileManager.fileExists(atPath: draftsDirectory.path) else { return }
        guard !fileManager.fileExists(atPath: markerURL.path) else { return }

        let jsonURLs = (try? fileManager.contentsOfDirectory(
            at: draftsDirectory,
            includingPropertiesForKeys: nil
        ))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        var convertedCount = 0
        var skippedCount = 0

        for jsonURL in jsonURLs {
            guard let data = try? Data(contentsOf: jsonURL),
                  let draft = try? JSONDecoder().decode(CatchDraft.self, from: data) else {
                skippedCount += 1
                Self.logger.info("Borrador omitido (JSON no decodificable): \(jsonURL.lastPathComponent, privacy: .public)")
                continue
            }

            guard !draft.photoPath.isEmpty else {
                skippedCount += 1
                Self.logger.info("Borrador omitido (foto ausente): \(jsonURL.lastPathComponent, privacy: .public)")
                continue
            }
            let photoURL = draftsDirectory.appendingPathComponent(draft.photoPath)
            guard let photoData = try? Data(contentsOf: photoURL), !photoData.isEmpty else {
                skippedCount += 1
                Self.logger.info("Borrador omitido (foto ausente): \(jsonURL.lastPathComponent, privacy: .public)")
                continue
            }

            _ = try await catchRepository.saveCatch(
                species: draft.species,
                photoData: photoData,
                date: draft.createdAt,
                location: nil,
                notes: ""
            )
            convertedCount += 1
        }

        guard fileManager.createFile(atPath: markerURL.path, contents: nil) else {
            Self.logger.error("Fallo al escribir el marker .migrated")
            throw CatchSaveError.writeFailed
        }

        Self.logger.info(
            "Migración completada: \(convertedCount, privacy: .public) convertidos, \(skippedCount, privacy: .public) omitidos"
        )
    }
}