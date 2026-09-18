import Foundation
import os

@testable import BetterFishing

enum CatchRepositoryFakeError: Error, Equatable {
    case saveFailed
    case updateFailed
    case deleteFailed
}

final class CatchRepositoryFake: CatchRepository, @unchecked Sendable {
    private struct State {
        var store: [UUID: Catch] = [:]
        var saveStub: Result<Catch, Error>?
        var updateStub: Result<Void, Error>?
        var deleteStub: Result<Void, Error>?
        var receivedSpecies: [Species] = []
        var receivedPhotoData: [Data] = []
        var receivedDates: [Date] = []
        var receivedLocations: [LocationCoordinate2D?] = []
        var receivedNotes: [String] = []
        var receivedSaveIDs: [UUID] = []
        var receivedUpdateIDs: [UUID] = []
        var receivedDeleteIDs: [UUID] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var saveStub: Result<Catch, Error>? {
        get { state.withLock { $0.saveStub } }
        set { state.withLock { $0.saveStub = newValue } }
    }

    var updateStub: Result<Void, Error>? {
        get { state.withLock { $0.updateStub } }
        set { state.withLock { $0.updateStub = newValue } }
    }

    var deleteStub: Result<Void, Error>? {
        get { state.withLock { $0.deleteStub } }
        set { state.withLock { $0.deleteStub = newValue } }
    }

    var receivedSpecies: [Species] {
        state.withLock { $0.receivedSpecies }
    }

    var receivedPhotoData: [Data] {
        state.withLock { $0.receivedPhotoData }
    }

    var receivedDates: [Date] {
        state.withLock { $0.receivedDates }
    }

    var receivedLocations: [LocationCoordinate2D?] {
        state.withLock { $0.receivedLocations }
    }

    var receivedNotes: [String] {
        state.withLock { $0.receivedNotes }
    }

    var receivedSaveIDs: [UUID] {
        state.withLock { $0.receivedSaveIDs }
    }

    var receivedUpdateIDs: [UUID] {
        state.withLock { $0.receivedUpdateIDs }
    }

    var receivedDeleteIDs: [UUID] {
        state.withLock { $0.receivedDeleteIDs }
    }

    var storedCatches: [Catch] {
        state.withLock { Array($0.store.values) }
    }

    func saveCatch(species: Species, photoData: Data, date: Date, location: LocationCoordinate2D?, notes: String) async throws -> Catch {
        let stub: Result<Catch, Error>? = state.withLock { state in
            state.receivedSpecies.append(species)
            state.receivedPhotoData.append(photoData)
            state.receivedDates.append(date)
            state.receivedLocations.append(location)
            state.receivedNotes.append(notes)
            return state.saveStub
        }
        if let stub {
            return try stub.get()
        }

        return state.withLock { state in
            let id = UUID()
            let saved = Catch(
                id: id,
                species: species,
                photoPath: "\(id.uuidString).jpg",
                date: date,
                location: location,
                notes: notes,
                createdAt: date
            )
            state.receivedSaveIDs.append(id)
            state.store[id] = saved
            return saved
        }
    }

    func listCatches() async throws -> [Catch] {
        state.withLock { Array($0.store.values) }
    }

    func getCatch(id: UUID) async throws -> Catch? {
        state.withLock { $0.store[id] }
    }

    func updateCatch(id: UUID, date: Date?, location: LocationCoordinate2D?, notes: String?) async throws {
        let stub: Result<Void, Error>? = state.withLock { state in
            state.receivedUpdateIDs.append(id)
            return state.updateStub
        }
        if let stub {
            try stub.get()
        }

        state.withLock { state in
            guard var catchEntry = state.store[id] else { return }
            if let date {
                catchEntry.date = date
            }
            catchEntry.location = location
            if let notes {
                catchEntry.notes = notes
            }
            state.store[id] = catchEntry
        }
    }

    func deleteCatch(id: UUID) async throws {
        let stub: Result<Void, Error>? = state.withLock { state in
            state.receivedDeleteIDs.append(id)
            return state.deleteStub
        }
        if let stub {
            try stub.get()
        }

        state.withLock { state in
            state.store[id] = nil
        }
    }
}