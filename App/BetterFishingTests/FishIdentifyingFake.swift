import Foundation
import os

@testable import BetterFishing

final class FishIdentifyingFake: FishIdentifying, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(
        initialState: (
            stubResult: Result<IdentificationOutcome, Error>.success(.noMatch),
            receivedImageData: [Data]()
        )
    )

    var stubResult: Result<IdentificationOutcome, Error> {
        get { state.withLock { $0.stubResult } }
        set { state.withLock { $0.stubResult = newValue } }
    }

    var receivedImageData: [Data] {
        state.withLock { $0.receivedImageData }
    }

    func recognize(imageData: Data) async throws -> IdentificationOutcome {
        let stub: Result<IdentificationOutcome, Error> = state.withLock { state in
            state.receivedImageData.append(imageData)
            return state.stubResult
        }
        return try stub.get()
    }
}