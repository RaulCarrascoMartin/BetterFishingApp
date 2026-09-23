import XCTest

@testable import BetterFishing

final class CatchSyncLedgerTests: XCTestCase {
    private func makeCatchFingerprint() -> Fingerprint {
        let species = Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
        let catchEntry = Catch(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            species: species,
            photoPath: "33333333-3333-3333-3333-333333333333.jpg",
            date: Date(timeIntervalSinceReferenceDate: 800_000_000),
            location: LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
            notes: "Capturada cerca del canal",
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_001)
        )
        return Fingerprint.of(catchEntry)
    }

    private func makeSnapshot() -> CatchSyncLedgerSnapshot {
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let tombstone = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let entry = CatchSyncLedgerEntry(
            lastLocalFingerprint: makeCatchFingerprint(),
            lastRemoteUpdatedAt: Date(timeIntervalSinceReferenceDate: 800_000_010),
            lastLocalPushedAt: Date(timeIntervalSinceReferenceDate: 800_000_020)
        )
        return CatchSyncLedgerSnapshot(
            entries: [id: entry],
            tombstonedIDs: [tombstone],
            lastSyncedRemoteIDs: [id, tombstone]
        )
    }

    func testCommitThenSnapshotRoundTrip() async throws {
        let directory = try makeTemporaryDirectory()
        let ledger = CatchSyncLedger(directoryURL: directory.url)
        let snapshot = makeSnapshot()

        try await ledger.commit(snapshot)

        let persistedPath = directory.url.appendingPathComponent("sync-ledger.json").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistedPath))

        let reread = try await ledger.snapshot()
        XCTAssertEqual(reread, snapshot)
        XCTAssertEqual(reread.entries.count, 1)
        XCTAssertEqual(reread.tombstonedIDs.count, 1)
        XCTAssertEqual(reread.lastSyncedRemoteIDs.count, 2)
    }

    func testSnapshotReturnsEmptyWhenFileMissing() async throws {
        let directory = try makeTemporaryDirectory()
        let ledger = CatchSyncLedger(directoryURL: directory.url)

        let snapshot = try await ledger.snapshot()

        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertTrue(snapshot.tombstonedIDs.isEmpty)
        XCTAssertTrue(snapshot.lastSyncedRemoteIDs.isEmpty)
    }

    func testCommitFailureDoesNotAlterPreviousSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        let ledger = CatchSyncLedger(directoryURL: directory.url)
        let snapshot = makeSnapshot()
        try await ledger.commit(snapshot)

        let blockedURL = directory.url.appendingPathComponent("ledger-blocked")
        try Data("blocker".utf8).write(to: blockedURL)
        let blockedLedger = CatchSyncLedger(directoryURL: blockedURL)
        let otherSnapshot = CatchSyncLedgerSnapshot(
            entries: [:],
            tombstonedIDs: [],
            lastSyncedRemoteIDs: []
        )

        do {
            try await blockedLedger.commit(otherSnapshot)
            XCTFail("commit debería lanzar al apuntar a un directorio inválido")
        } catch {
            // Esperado: la creación del directorio falla porque la ruta está ocupada por un fichero.
        }

        let reloaded = CatchSyncLedger(directoryURL: directory.url)
        let reread = try await reloaded.snapshot()
        XCTAssertEqual(reread, snapshot)
    }

    func testFingerprintIsDeterministicForEqualCatches() {
        let species = Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let location = LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
        let catchEntry = Catch(
            id: id,
            species: species,
            photoPath: "33333333-3333-3333-3333-333333333333.jpg",
            date: date,
            location: location,
            notes: "Capturada cerca del canal",
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_001)
        )
        let otherPhotoAndCreated = Catch(
            id: id,
            species: species,
            photoPath: "otro.jpg",
            date: date,
            location: location,
            notes: "Capturada cerca del canal",
            createdAt: Date(timeIntervalSinceReferenceDate: 900_000_000)
        )

        XCTAssertEqual(Fingerprint.of(catchEntry), Fingerprint.of(catchEntry))
        XCTAssertEqual(Fingerprint.of(catchEntry), Fingerprint.of(otherPhotoAndCreated))
        if case .sha256(let digest) = Fingerprint.of(catchEntry) {
            XCTAssertEqual(digest.count, 64)
        } else {
            XCTFail("Fingerprint debería ser sha256")
        }
    }
}