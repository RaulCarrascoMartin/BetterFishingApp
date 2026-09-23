import Foundation

enum CatchSyncAction: Sendable, Equatable {
    case push(Catch)
    case pull(RemoteCatch)
    case skip

    static func == (lhs: CatchSyncAction, rhs: CatchSyncAction) -> Bool {
        switch (lhs, rhs) {
        case (.skip, .skip):
            return true
        case let (.push(lhsCatch), .push(rhsCatch)):
            return catchEqual(lhsCatch, rhsCatch)
        case let (.pull(lhsRemote), .pull(rhsRemote)):
            return lhsRemote == rhsRemote
        default:
            return false
        }
    }
}

private func catchEqual(_ lhs: Catch, _ rhs: Catch) -> Bool {
    lhs.id == rhs.id
        && lhs.species == rhs.species
        && lhs.photoPath == rhs.photoPath
        && lhs.date == rhs.date
        && lhs.location == rhs.location
        && lhs.notes == rhs.notes
        && lhs.createdAt == rhs.createdAt
}

struct CatchSyncMergerInput: Sendable, Equatable {
    let local: Catch?
    let remote: RemoteCatch?
    let localFingerprint: Fingerprint?
    let ledger: CatchSyncLedgerSnapshot
    let now: Date

    static func == (lhs: CatchSyncMergerInput, rhs: CatchSyncMergerInput) -> Bool {
        switch (lhs.local, rhs.local) {
        case (nil, nil):
            return true
        case let (lhsLocal?, rhsLocal?):
            guard catchEqual(lhsLocal, rhsLocal) else { return false }
        default:
            return false
        }
        return lhs.remote == rhs.remote
            && lhs.localFingerprint == rhs.localFingerprint
            && lhs.ledger == rhs.ledger
            && lhs.now == rhs.now
    }
}

struct CatchSyncMerger {
    static func decide(for id: UUID, input: CatchSyncMergerInput) -> CatchSyncAction {
        guard let local = input.local else {
            guard let remote = input.remote else {
                return .skip
            }
            if input.ledger.tombstonedIDs.contains(id) {
                return .skip
            }
            return .pull(remote)
        }
        guard let remote = input.remote else {
            return .push(local)
        }
        let entry = input.ledger.entries[id]
        let remoteChanged = remote.updatedAt != entry?.lastRemoteUpdatedAt
        let localChanged = input.localFingerprint != entry?.lastLocalFingerprint

        if !remoteChanged && !localChanged {
            return .skip
        }
        if !localChanged && remoteChanged {
            return .pull(remote)
        }
        if localChanged && !remoteChanged {
            return .push(local)
        }
        let lastLocalPushedAt = entry?.lastLocalPushedAt ?? input.now
        if remote.updatedAt > lastLocalPushedAt {
            return .pull(remote)
        }
        return .push(local)
    }
}