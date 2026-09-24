import XCTest

@testable import BetterFishing

actor RecordingDB: SupabaseDatabaseAccess {
    private var rowsScript: [[String]]
    private var lastBatch: [String] = []
    private let cannedRPCValue: String
    private var recordedSelectValues: [BaseFakeRecordedSelect] = []
    private var recordedRPCValues: [BaseFakeRecordedRPC] = []

    init(rowsScript: [[String]], cannedRPCValue: String = "{}") {
        self.rowsScript = rowsScript
        self.cannedRPCValue = cannedRPCValue
    }

    var recordedSelects: [BaseFakeRecordedSelect] { recordedSelectValues }
    var recordedRPCs: [BaseFakeRecordedRPC] { recordedRPCValues }

    func select<T: Decodable & Sendable>(
        columns: String,
        from table: String,
        filters: [SupabaseFilter],
        limit: Int?
    ) async throws -> [T] {
        recordedSelectValues.append(
            BaseFakeRecordedSelect(columns: columns, table: table, filters: filters, limit: limit)
        )
        if rowsScript.isEmpty {
            return try lastBatch.compactMap { try JSONDecoder().decode(T.self, from: Data($0.utf8)) }
        }
        lastBatch = rowsScript.removeFirst()
        return try lastBatch.compactMap { try JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }

    func rpc<T: Decodable & Sendable>(
        _ function: String,
        arguments: SupabaseRPCArguments?
    ) async throws -> T {
        recordedRPCValues.append(BaseFakeRecordedRPC(function: function, arguments: arguments))
        return try JSONDecoder().decode(T.self, from: Data(cannedRPCValue.utf8))
    }
}

final class CatchSyncServiceTests: XCTestCase {
    private let referenceTime: TimeInterval = 800_000_000
    private let userID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let idA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let idB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    private func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
    }

    private func makeLocation() -> LocationCoordinate2D {
        LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
    }

    private func makeLocalCatch(
        id: UUID,
        notes: String = "Capturada cerca del canal",
        date: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    ) -> Catch {
        Catch(
            id: id,
            species: makeSpecies(),
            photoPath: "\(id.uuidString).jpg",
            date: date,
            location: makeLocation(),
            notes: notes,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_001)
        )
    }

    private func makeRemoteCatch(
        id: UUID,
        updatedAt: TimeInterval,
        notes: String = "Capturada cerca del canal"
    ) -> RemoteCatch {
        RemoteCatch(
            id: id,
            userID: userID,
            species: makeSpecies(),
            date: Date(timeIntervalSinceReferenceDate: 800_000_000),
            location: makeLocation(),
            notes: notes,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_001),
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt),
            photoPath: "\(userID.uuidString)/\(id.uuidString).jpg"
        )
    }

    private func remoteRowJSON(_ remote: RemoteCatch) throws -> String {
        String(decoding: try JSONEncoder().encode(remote), as: UTF8.self)
    }

    private func seedCatch(
        in directory: TemporaryTestDirectory,
        catchEntry: Catch,
        photoData: Data? = nil
    ) throws {
        let jsonURL = directory.url.appendingPathComponent("\(catchEntry.id.uuidString).json")
        try JSONEncoder().encode(catchEntry).write(to: jsonURL, options: .atomic)
        if let photoData {
            try photoData.write(
                to: directory.url.appendingPathComponent("\(catchEntry.id.uuidString).jpg"),
                options: .atomic
            )
        }
    }

    private func makeFixture(in directory: TemporaryTestDirectory) -> (
        repository: LocalFileCatchRepository,
        store: FileSyncCatchStore,
        ledger: CatchSyncLedger
    ) {
        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let store = FileSyncCatchStore(directoryURL: directory.url)
        let ledger = CatchSyncLedger(directoryURL: directory.url)
        return (repository, store, ledger)
    }

    private func makeService(
        directory: TemporaryTestDirectory,
        repository: LocalFileCatchRepository,
        store: FileSyncCatchStore,
        ledger: CatchSyncLedger,
        database: any SupabaseDatabaseAccess,
        storage: any SupabaseStoring
    ) -> CatchSyncService {
        CatchSyncService(
            repository: repository,
            photoDataProvider: { catchEntry in
                try? Data(contentsOf: directory.url.appendingPathComponent("\(catchEntry.id.uuidString).jpg"))
            },
            localStore: store,
            ledger: ledger,
            database: database,
            storage: storage
        )
    }

    func testPushLocalCatchesIdempotent() async throws {
        let directory = try makeTemporaryDirectory()
        let fixture = makeFixture(in: directory)
        try seedCatch(in: directory, catchEntry: makeLocalCatch(id: idA), photoData: Data([0xAA]))
        try seedCatch(in: directory, catchEntry: makeLocalCatch(id: idB), photoData: Data([0xBB]))

        let remoteA = makeRemoteCatch(id: idA, updatedAt: referenceTime + 1000)
        let remoteB = makeRemoteCatch(id: idB, updatedAt: referenceTime + 2000)
        let db = RecordingDB(rowsScript: [[], [try remoteRowJSON(remoteA), try remoteRowJSON(remoteB)]])
        let storage = SupabaseBaseFake()
        let service = makeService(
            directory: directory,
            repository: fixture.repository,
            store: fixture.store,
            ledger: fixture.ledger,
            database: db,
            storage: storage
        )

        let first = try await service.sync(userID: userID)
        XCTAssertEqual(first.pushed, 2)
        XCTAssertEqual(first.skipped, 0)

        let second = try await service.sync(userID: userID)
        XCTAssertEqual(second.pushed, 0)
        XCTAssertEqual(second.skipped, 2)

        let rpcs = await db.recordedRPCs
        XCTAssertEqual(rpcs.count, 2)
        XCTAssertTrue(rpcs.allSatisfy { $0.function == "upsert_catch" })
        let remoteCatchForA = await db.recordedSelects
        XCTAssertEqual(remoteCatchForA.count, 3)
    }

    func testPullRemoteCatchesPreservingID() async throws {
        let directory = try makeTemporaryDirectory()
        let fixture = makeFixture(in: directory)

        let remoteA = makeRemoteCatch(id: idA, updatedAt: referenceTime + 1000)
        let remoteB = makeRemoteCatch(id: idB, updatedAt: referenceTime + 2000)
        let db = SupabaseBaseFake(cannedRows: [try remoteRowJSON(remoteA), try remoteRowJSON(remoteB)])
        db.downloadResultData = Data([0x01, 0x02, 0x03])
        let service = makeService(
            directory: directory,
            repository: fixture.repository,
            store: fixture.store,
            ledger: fixture.ledger,
            database: db,
            storage: db
        )

        let result = try await service.sync(userID: userID)
        XCTAssertEqual(result.pulled, 2)
        XCTAssertEqual(result.pushed, 0)

        let listed = try await fixture.repository.listCatches()
        XCTAssertEqual(listed.count, 2)
        let listedSorted = listed.map(\.id).sorted { $0.uuidString < $1.uuidString }
        XCTAssertEqual(listedSorted, [idA, idB].sorted { $0.uuidString < $1.uuidString })

        let localA = try await fixture.store.localCatch(id: idA)
        XCTAssertEqual(localA?.id, idA)
        XCTAssertEqual(localA?.notes, remoteA.notes)
        XCTAssertEqual(localA?.photoPath, "\(idA.uuidString).jpg")
        XCTAssertEqual(fixture.repository.photoData(for: localA!), Data([0x01, 0x02, 0x03]))

        let photoA = await fixture.store.photoData(for: idA)
        XCTAssertEqual(photoA, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(db.recordedDownloads.count, 2)
    }

    func testTombstoneBlocksRedownload() async throws {
        let directory = try makeTemporaryDirectory()
        let fixture = makeFixture(in: directory)
        try seedCatch(in: directory, catchEntry: makeLocalCatch(id: idA), photoData: Data([0xAA]))

        let remoteA = makeRemoteCatch(id: idA, updatedAt: referenceTime + 1000)
        let db = RecordingDB(rowsScript: [[], [try remoteRowJSON(remoteA)]])
        let storage = SupabaseBaseFake()
        let service = makeService(
            directory: directory,
            repository: fixture.repository,
            store: fixture.store,
            ledger: fixture.ledger,
            database: db,
            storage: storage
        )

        let first = try await service.sync(userID: userID)
        XCTAssertEqual(first.pushed, 1)

        try await fixture.repository.deleteCatch(id: idA)

        let second = try await service.sync(userID: userID)
        XCTAssertEqual(second.pulled, 0)
        XCTAssertEqual(second.pushed, 0)
        XCTAssertEqual(second.skipped, 1)

        let listed = try await fixture.repository.listCatches()
        XCTAssertTrue(listed.isEmpty)
        let snapshot = try await fixture.ledger.snapshot()
        XCTAssertTrue(snapshot.tombstonedIDs.contains(idA))
    }

    func testLWWConflictLocalNewerPushes() async throws {
        let directory = try makeTemporaryDirectory()
        let fixture = makeFixture(in: directory)
        try seedCatch(in: directory, catchEntry: makeLocalCatch(id: idA, notes: "Nota local nueva"), photoData: Data([0xAA]))

        let oldLocal = makeLocalCatch(id: idA, notes: "Nota vieja")
        let oldFingerprint = Fingerprint.of(oldLocal)
        let initialSnapshot = CatchSyncLedgerSnapshot(
            entries: [
                idA: CatchSyncLedgerEntry(
                    lastLocalFingerprint: oldFingerprint,
                    lastRemoteUpdatedAt: Date(timeIntervalSinceReferenceDate: referenceTime + 100),
                    lastLocalPushedAt: Date(timeIntervalSinceReferenceDate: referenceTime + 300)
                )
            ],
            tombstonedIDs: [],
            lastSyncedRemoteIDs: [idA]
        )
        try await fixture.ledger.commit(initialSnapshot)

        let remoteA = makeRemoteCatch(id: idA, updatedAt: referenceTime + 200)
        let db = SupabaseBaseFake(cannedRows: [try remoteRowJSON(remoteA)], cannedRPCValue: "{}")
        let service = makeService(
            directory: directory,
            repository: fixture.repository,
            store: fixture.store,
            ledger: fixture.ledger,
            database: db,
            storage: db
        )

        let result = try await service.sync(userID: userID)
        XCTAssertEqual(result.pushed, 1)
        XCTAssertEqual(result.pulled, 0)

        let rpc = try XCTUnwrap(db.recordedRPCs.first)
        XCTAssertEqual(rpc.function, "upsert_catch")
        guard case .string(let payload)? = rpc.arguments?.values["p_catch"] else {
            XCTFail("p_catch debe ser un string JSON del catch")
            return
        }
        XCTAssertTrue(payload.contains(idA.uuidString))
        XCTAssertFalse(payload.contains("Nota vieja"))
        XCTAssertTrue(payload.contains("Nota local nueva"))
    }

    func testNetworkFailureLeavesLocalAndLedgerIntact() async throws {
        let directory = try makeTemporaryDirectory()
        let fixture = makeFixture(in: directory)
        try seedCatch(in: directory, catchEntry: makeLocalCatch(id: idA), photoData: Data([0xAA]))

        let db = SupabaseBaseFake()
        db.databaseError = SupabaseBaseError.queryFailed
        let service = makeService(
            directory: directory,
            repository: fixture.repository,
            store: fixture.store,
            ledger: fixture.ledger,
            database: db,
            storage: db
        )

        do {
            _ = try await service.sync(userID: userID)
            XCTFail("sync debería lanzar CatchSyncError.remoteLoadFailed")
        } catch let error as CatchSyncError {
            guard case .remoteLoadFailed = error else {
                XCTFail("Se esperaba .remoteLoadFailed, recibido \(error)")
                return
            }
        }

        let listed = try await fixture.repository.listCatches()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.id, idA)

        let snapshot = try await fixture.ledger.snapshot()
        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertTrue(snapshot.tombstonedIDs.isEmpty)
        XCTAssertTrue(snapshot.lastSyncedRemoteIDs.isEmpty)
    }

    func testUploadFailureDuringPushLeavesLocalAndLedgerIntact() async throws {
        let directory = try makeTemporaryDirectory()
        let fixture = makeFixture(in: directory)
        try seedCatch(in: directory, catchEntry: makeLocalCatch(id: idA), photoData: Data([0xAA]))

        let db = SupabaseBaseFake()
        db.uploadError = SupabaseBaseError.uploadFailed
        let service = makeService(
            directory: directory,
            repository: fixture.repository,
            store: fixture.store,
            ledger: fixture.ledger,
            database: db,
            storage: db
        )

        do {
            _ = try await service.sync(userID: userID)
            XCTFail("sync debería lanzar CatchSyncError.pushFailed")
        } catch let error as CatchSyncError {
            guard case .pushFailed = error else {
                XCTFail("Se esperaba .pushFailed, recibido \(error)")
                return
            }
        }

        let listed = try await fixture.repository.listCatches()
        XCTAssertEqual(listed.count, 1)

        let snapshot = try await fixture.ledger.snapshot()
        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertTrue(snapshot.tombstonedIDs.isEmpty)
        XCTAssertTrue(snapshot.lastSyncedRemoteIDs.isEmpty)
    }

    func testPullContinuesImportingWhenPhotoDownloadFails() async throws {
        let directory = try makeTemporaryDirectory()
        let fixture = makeFixture(in: directory)

        let remoteA = makeRemoteCatch(id: idA, updatedAt: referenceTime + 1000)
        let db = SupabaseBaseFake(cannedRows: [try remoteRowJSON(remoteA)])
        db.downloadError = SupabaseBaseError.downloadFailed
        let service = makeService(
            directory: directory,
            repository: fixture.repository,
            store: fixture.store,
            ledger: fixture.ledger,
            database: db,
            storage: db
        )

        let result = try await service.sync(userID: userID)
        XCTAssertEqual(result.pulled, 1)

        let local = try await fixture.store.localCatch(id: idA)
        XCTAssertEqual(local?.id, idA)
        let photo = await fixture.store.photoData(for: idA)
        XCTAssertNil(photo)
    }
}