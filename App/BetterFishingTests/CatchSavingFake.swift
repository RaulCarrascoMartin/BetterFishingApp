import Foundation
import os

@testable import BetterFishing

enum CatchSavingFakeError: Error, Equatable {
    case saveFailed
}

final class CatchSavingFake: CatchSaving, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(
        initialState: (
            stubResult: Result<Void, Error>.success(()),
            receivedSpecies: [Species](),
            receivedPhotoData: [Data]()
        )
    )

    var stubResult: Result<Void, Error> {
        get { state.withLock { $0.stubResult } }
        set { state.withLock { $0.stubResult = newValue } }
    }

    var receivedSpecies: [Species] {
        state.withLock { $0.receivedSpecies }
    }

    var receivedPhotoData: [Data] {
        state.withLock { $0.receivedPhotoData }
    }

    func saveDraft(species: Species, photoData: Data) async throws {
        let stub: Result<Void, Error> = state.withLock { state in
            state.receivedSpecies.append(species)
            state.receivedPhotoData.append(photoData)
            return state.stubResult
        }
        try stub.get()
    }
}