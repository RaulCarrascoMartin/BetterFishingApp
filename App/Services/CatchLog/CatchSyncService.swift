import Foundation
import os

actor CatchSyncService: CatchSynchronizing {
    private static let logger = Logger(subsystem: "com.betterfishing.BetterFishing", category: "CatchSync")

    private let repository: any CatchRepository
    private let photoDataProvider: @Sendable (Catch) -> Data?
    private let localStore: any SyncCatchLocalStore
    private let ledger: CatchSyncLedger
    private let database: any SupabaseDatabaseAccess
    private let storage: any SupabaseStoring

    init(
        repository: any CatchRepository,
        photoDataProvider: @escaping @Sendable (Catch) -> Data?,
        localStore: any SyncCatchLocalStore,
        ledger: CatchSyncLedger,
        database: any SupabaseDatabaseAccess,
        storage: any SupabaseStoring
    ) {
        self.repository = repository
        self.photoDataProvider = photoDataProvider
        self.localStore = localStore
        self.ledger = ledger
        self.database = database
        self.storage = storage
    }

    func sync(userID: UUID) async throws -> CatchSyncResult {
        let remoteColumns = "id,user_id,species,date,location,notes,created_at,updated_at,photo_path"

        let local = try await repository.listCatches()
        let remote: [RemoteCatch]
        do {
            remote = try await database.select(
                columns: remoteColumns,
                from: "catches",
                filters: [SupabaseFilter(column: "user_id", operator: .eq, value: userID.uuidString)],
                limit: nil
            )
        } catch {
            Self.logger.error("Fallo la lectura remota de capturas: \(error.localizedDescription, privacy: .public)")
            throw CatchSyncError.remoteLoadFailed(Self.errorText(error))
        }

        let loaded: CatchSyncLedgerSnapshot
        do {
            loaded = try await ledger.snapshot()
        } catch {
            throw CatchSyncError.ledgerFailed(Self.errorText(error))
        }

        let now = Date()
        var localByID: [UUID: Catch] = [:]
        for catchEntry in local {
            localByID[catchEntry.id] = catchEntry
        }
        var remoteByID: [UUID: RemoteCatch] = [:]
        for catchEntry in remote {
            remoteByID[catchEntry.id] = catchEntry
        }

        var newSnapshot = loaded
        let derivedTombstones = loaded.lastSyncedRemoteIDs.subtracting(Set(localByID.keys))
        newSnapshot.tombstonedIDs.formUnion(derivedTombstones)
        var decisionSnapshot = loaded
        decisionSnapshot.tombstonedIDs.formUnion(derivedTombstones)

        var pushed = 0
        var pulled = 0
        var skipped = 0
        var pushedIDs: [UUID] = []

        let mergedIDs = Set(localByID.keys).union(Set(remoteByID.keys))
            .sorted { $0.uuidString < $1.uuidString }

        for id in mergedIDs {
            let localCatch = localByID[id]
            let remoteCatch = remoteByID[id]
            let input = CatchSyncMergerInput(
                local: localCatch,
                remote: remoteCatch,
                localFingerprint: localCatch.map(Fingerprint.of),
                ledger: decisionSnapshot,
                now: now
            )
            switch CatchSyncMerger.decide(for: id, input: input) {
            case .push(let catchEntry):
                try await performPush(catchEntry, userID: userID)
                pushed += 1
                pushedIDs.append(id)
                var entry = loaded.entries[id] ?? CatchSyncLedgerEntry()
                entry.lastLocalFingerprint = Fingerprint.of(catchEntry)
                entry.lastLocalPushedAt = now
                newSnapshot.entries[id] = entry
            case .pull(let remoteEntry):
                let imported = try await performPull(remoteEntry)
                pulled += 1
                var entry = loaded.entries[id] ?? CatchSyncLedgerEntry()
                entry.lastLocalFingerprint = Fingerprint.of(imported)
                entry.lastRemoteUpdatedAt = remoteEntry.updatedAt
                newSnapshot.entries[id] = entry
            case .skip:
                skipped += 1
            }
        }

        var finalRemoteRows = remote
        if pushed > 0 {
            var authoritativeUpdatedAt: [UUID: Date] = [:]
            do {
                let rows: [RemoteCatch] = try await database.select(
                    columns: remoteColumns,
                    from: "catches",
                    filters: [SupabaseFilter(column: "user_id", operator: .eq, value: userID.uuidString)],
                    limit: nil
                )
                finalRemoteRows = rows
                for row in rows {
                    authoritativeUpdatedAt[row.id] = row.updatedAt
                }
            } catch {
                throw CatchSyncError.remoteLoadFailed(Self.errorText(error))
            }
            for id in pushedIDs {
                if var entry = newSnapshot.entries[id] {
                    entry.lastRemoteUpdatedAt = authoritativeUpdatedAt[id]
                    newSnapshot.entries[id] = entry
                }
            }
        }
        newSnapshot.lastSyncedRemoteIDs = Set(finalRemoteRows.map(\.id))

        do {
            try await ledger.commit(newSnapshot)
        } catch {
            Self.logger.error("Fallo el commit del ledger: \(error.localizedDescription, privacy: .public)")
            throw CatchSyncError.ledgerFailed(Self.errorText(error))
        }

        Self.logger.info(
            "Sync completada: pushed=\(pushed, privacy: .public), pulled=\(pulled, privacy: .public), skipped=\(skipped, privacy: .public), tombstones=\(newSnapshot.tombstonedIDs.count, privacy: .public)"
        )
        return CatchSyncResult(pushed: pushed, pulled: pulled, skipped: skipped)
    }

    private func performPush(_ catchEntry: Catch, userID: UUID) async throws {
        if let photo = photoDataProvider(catchEntry) {
            do {
                _ = try await storage.upload(
                    bucket: "catches",
                    path: "\(userID.uuidString)/\(catchEntry.id.uuidString).jpg",
                    data: photo,
                    options: SupabaseUploadOptions(contentType: "image/jpeg", upsert: true)
                )
            } catch {
                Self.logger.error("Fallo la subida de la foto de \(catchEntry.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw CatchSyncError.pushFailed(Self.errorText(error))
            }
        }

        let payload = CatchPushPayload(catchEntry: catchEntry, userID: userID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let catchJSON: String
        do {
            let data = try encoder.encode(payload)
            catchJSON = String(decoding: data, as: UTF8.self)
        } catch {
            throw CatchSyncError.pushFailed(Self.errorText(error))
        }
        do {
            try await database.rpcVoid(
                "upsert_catch",
                arguments: SupabaseRPCArguments([
                    "p_user_id": .string(userID.uuidString),
                    "p_catch": .string(catchJSON)
                ])
            )
        } catch {
            Self.logger.error("Fallo el upsert de \(catchEntry.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw CatchSyncError.pushFailed(Self.errorText(error))
        }
    }

    private func performPull(_ remote: RemoteCatch) async throws -> Catch {
        var local = try await remote.asCatch()
        local = Catch(
            id: local.id,
            species: local.species,
            photoPath: "\(local.id.uuidString).jpg",
            date: local.date,
            location: local.location,
            notes: local.notes,
            createdAt: local.createdAt
        )
        let photoData: Data?
        if let photoPath = remote.photoPath {
            if let data = try? await storage.download(bucket: "catches", path: photoPath) {
                photoData = data
            } else {
                Self.logger.warning("No se pudo descargar la foto de \(remote.id.uuidString, privacy: .public); se importa sin foto.")
                photoData = nil
            }
        } else {
            photoData = nil
        }
        do {
            try await localStore.importCatch(local, photoData: photoData)
        } catch {
            Self.logger.error("Fallo la importacion local de \(remote.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw CatchSyncError.pullFailed(Self.errorText(error))
        }
        return local
    }

    private static func errorText(_ error: Error) -> String {
        error.localizedDescription
    }
}

private struct CatchPushPayload: Encodable {
    let id: UUID
    let species: Species
    let date: Date
    let location: LocationCoordinate2D?
    let notes: String
    let createdAt: Date
    let photoPath: String

    init(catchEntry: Catch, userID: UUID) {
        self.id = catchEntry.id
        self.species = catchEntry.species
        self.date = catchEntry.date
        self.location = catchEntry.location
        self.notes = catchEntry.notes
        self.createdAt = catchEntry.createdAt
        self.photoPath = "\(userID.uuidString)/\(catchEntry.id.uuidString).jpg"
    }
}