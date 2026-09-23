import XCTest

@testable import BetterFishing

final class CatchSyncMergerTests: XCTestCase {
    private let referenceTime: TimeInterval = 800_000_000
    private let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let userID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let fingerprintA = Fingerprint.sha256("a")
    private let fingerprintB = Fingerprint.sha256("b")

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

    private func makeLocal() -> Catch {
        Catch(
            id: id,
            species: makeSpecies(),
            photoPath: "\(id.uuidString).jpg",
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: makeLocation(),
            notes: "Capturada cerca del canal",
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime + 1)
        )
    }

    private func makeRemote(updatedAt: TimeInterval) -> RemoteCatch {
        RemoteCatch(
            id: id,
            userID: userID,
            species: makeSpecies(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: makeLocation(),
            notes: "Capturada cerca del canal",
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime + 1),
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt),
            photoPath: "\(id.uuidString).jpg"
        )
    }

    private func makeEntry(
        localFingerprint: Fingerprint,
        remoteUpdatedAt: TimeInterval,
        lastLocalPushedAt: TimeInterval
    ) -> CatchSyncLedgerEntry {
        CatchSyncLedgerEntry(
            lastLocalFingerprint: localFingerprint,
            lastRemoteUpdatedAt: Date(timeIntervalSinceReferenceDate: remoteUpdatedAt),
            lastLocalPushedAt: Date(timeIntervalSinceReferenceDate: lastLocalPushedAt)
        )
    }

    private func makeSnapshot(
        entry: CatchSyncLedgerEntry? = nil,
        tombstoneID: UUID? = nil
    ) -> CatchSyncLedgerSnapshot {
        var entries: [UUID: CatchSyncLedgerEntry] = [:]
        if let entry {
            entries[id] = entry
        }
        return CatchSyncLedgerSnapshot(
            entries: entries,
            tombstonedIDs: tombstoneID.map { [$0] } ?? [],
            lastSyncedRemoteIDs: []
        )
    }

    private func makeInput(
        local: Catch?,
        remote: RemoteCatch?,
        localFingerprint: Fingerprint?,
        ledger: CatchSyncLedgerSnapshot,
        now: TimeInterval = 800_002_000
    ) -> CatchSyncMergerInput {
        CatchSyncMergerInput(
            local: local,
            remote: remote,
            localFingerprint: localFingerprint,
            ledger: ledger,
            now: Date(timeIntervalSinceReferenceDate: now)
        )
    }

    func testOnlyLocalPushes() {
        let local = makeLocal()

        let action = CatchSyncMerger.decide(
            for: id,
            input: makeInput(local: local, remote: nil, localFingerprint: nil, ledger: makeSnapshot())
        )

        XCTAssertEqual(action, .push(local))
    }

    func testOnlyRemotePulls() {
        let remote = makeRemote(updatedAt: referenceTime + 200)

        let action = CatchSyncMerger.decide(
            for: id,
            input: makeInput(local: nil, remote: remote, localFingerprint: nil, ledger: makeSnapshot())
        )

        XCTAssertEqual(action, .pull(remote))
    }

    func testBothUnchangedSkips() {
        let local = makeLocal()
        let remote = makeRemote(updatedAt: referenceTime + 200)
        let entry = makeEntry(
            localFingerprint: fingerprintA,
            remoteUpdatedAt: referenceTime + 200,
            lastLocalPushedAt: referenceTime + 300
        )

        let action = CatchSyncMerger.decide(
            for: id,
            input: makeInput(
                local: local,
                remote: remote,
                localFingerprint: fingerprintA,
                ledger: makeSnapshot(entry: entry)
            )
        )

        XCTAssertEqual(action, .skip)
    }

    func testOnlyLocalChangedPushes() {
        let local = makeLocal()
        let remote = makeRemote(updatedAt: referenceTime + 200)
        let entry = makeEntry(
            localFingerprint: fingerprintA,
            remoteUpdatedAt: referenceTime + 200,
            lastLocalPushedAt: referenceTime + 300
        )

        let action = CatchSyncMerger.decide(
            for: id,
            input: makeInput(
                local: local,
                remote: remote,
                localFingerprint: fingerprintB,
                ledger: makeSnapshot(entry: entry)
            )
        )

        XCTAssertEqual(action, .push(local))
    }

    func testOnlyRemoteChangedPulls() {
        let local = makeLocal()
        let remote = makeRemote(updatedAt: referenceTime + 250)
        let entry = makeEntry(
            localFingerprint: fingerprintA,
            remoteUpdatedAt: referenceTime + 200,
            lastLocalPushedAt: referenceTime + 300
        )

        let action = CatchSyncMerger.decide(
            for: id,
            input: makeInput(
                local: local,
                remote: remote,
                localFingerprint: fingerprintA,
                ledger: makeSnapshot(entry: entry)
            )
        )

        XCTAssertEqual(action, .pull(remote))
    }

    func testBothChangedRemoteNewerPulls() {
        let local = makeLocal()
        let remote = makeRemote(updatedAt: referenceTime + 400)
        let entry = makeEntry(
            localFingerprint: fingerprintA,
            remoteUpdatedAt: referenceTime + 200,
            lastLocalPushedAt: referenceTime + 300
        )

        let action = CatchSyncMerger.decide(
            for: id,
            input: makeInput(
                local: local,
                remote: remote,
                localFingerprint: fingerprintB,
                ledger: makeSnapshot(entry: entry)
            )
        )

        XCTAssertEqual(action, .pull(remote))
    }

    func testBothChangedLocalLastPushedNewerPushes() {
        let local = makeLocal()
        let remote = makeRemote(updatedAt: referenceTime + 300)
        let entry = makeEntry(
            localFingerprint: fingerprintA,
            remoteUpdatedAt: referenceTime + 200,
            lastLocalPushedAt: referenceTime + 400
        )

        let action = CatchSyncMerger.decide(
            for: id,
            input: makeInput(
                local: local,
                remote: remote,
                localFingerprint: fingerprintB,
                ledger: makeSnapshot(entry: entry)
            )
        )

        XCTAssertEqual(action, .push(local))
    }

    func testExactTiePushes() {
        let local = makeLocal()
        let remote = makeRemote(updatedAt: referenceTime + 400)
        let entry = makeEntry(
            localFingerprint: fingerprintA,
            remoteUpdatedAt: referenceTime + 200,
            lastLocalPushedAt: referenceTime + 400
        )

        let action = CatchSyncMerger.decide(
            for: id,
            input: makeInput(
                local: local,
                remote: remote,
                localFingerprint: fingerprintB,
                ledger: makeSnapshot(entry: entry)
            )
        )

        XCTAssertEqual(action, .push(local))
    }

    func testTombstoneBlocksPull() {
        let remote = makeRemote(updatedAt: referenceTime + 200)

        let action = CatchSyncMerger.decide(
            for: id,
            input: makeInput(
                local: nil,
                remote: remote,
                localFingerprint: nil,
                ledger: makeSnapshot(tombstoneID: id)
            )
        )

        XCTAssertEqual(action, .skip)
    }

    func testBrandNewIDNeverSyncedDefaultsToNowPushes() {
        let local = makeLocal()
        let remote = makeRemote(updatedAt: referenceTime + 200)

        let action = CatchSyncMerger.decide(
            for: id,
            input: makeInput(
                local: local,
                remote: remote,
                localFingerprint: fingerprintB,
                ledger: makeSnapshot()
            )
        )

        XCTAssertEqual(action, .push(local))
    }
}