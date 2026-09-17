import XCTest
import os

@testable import BetterFishing

@MainActor
final class FishScannerViewModelTests: XCTestCase {
    private let rawImage = Data([0x01, 0x02, 0x03])
    private let preparedImage = Data([0xFF, 0xD8, 0xFF])

    private func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
    }

    private func makeResult() -> IdentificationResult {
        IdentificationResult(species: makeSpecies(), certainty: 0.87, confidence: .reliable)
    }

    private func makeViewModel(
        identifier: any FishIdentifying,
        preparer: any ImagePreparing = ImagePreparingFake(),
        catchSaver: any CatchSaving = CatchSavingFake()
    ) -> FishScannerViewModel {
        FishScannerViewModel(identifier: identifier, imagePreparer: preparer, catchSaver: catchSaver)
    }

    func testInitialStateIsIdle() {
        let viewModel = makeViewModel(identifier: FishIdentifyingFake())

        XCTAssertEqual(viewModel.scanState, .idle)
    }

    func testSetImageAutoStartsAndIdentifiesUsingPreparedData() async {
        let identifier = FishIdentifyingFake()
        let result = makeResult()
        identifier.stubResult = .success(.identified(result))
        let preparer = ImagePreparingFake()
        preparer.stubResult = .success(preparedImage)
        let viewModel = makeViewModel(identifier: identifier, preparer: preparer)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .identified(result) }

        XCTAssertEqual(viewModel.scanState, .identified(result))
        XCTAssertEqual(
            preparer.receivedData,
            [rawImage],
            "La imagen original debe pasar primero por la preparación"
        )
        XCTAssertEqual(
            identifier.receivedImageData,
            [preparedImage],
            "FishIdentifying debe recibir la imagen preparada, no la original"
        )
    }

    func testSetImageTransitionsThroughIdentifyingWhileInFlight() async {
        let identifier = SuspendedFishIdentifying()
        let viewModel = makeViewModel(identifier: identifier)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .identifying && identifier.isSuspended }

        XCTAssertEqual(
            viewModel.scanState,
            .identifying,
            "Mientras la identificación está en curso debe aplicarse el estado de carga"
        )

        identifier.release(result: .success(.identified(makeResult())))
        await waitUntil { viewModel.scanState == .identified(self.makeResult()) }

        XCTAssertEqual(viewModel.scanState, .identified(makeResult()))
    }

    func testSetImageWithNoMatchOutcomeShowsNoMatch() async {
        let identifier = FishIdentifyingFake()
        identifier.stubResult = .success(.noMatch)
        let viewModel = makeViewModel(identifier: identifier)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .noMatch }

        XCTAssertEqual(viewModel.scanState, .noMatch)
    }

    func testIdentifyFailureYieldsFailedMessage() async {
        let identifier = SuspendedFishIdentifying()
        let viewModel = makeViewModel(identifier: identifier)

        viewModel.setImage(data: rawImage)
        await waitUntil { identifier.isSuspended }
        identifier.release(result: .failure(RecognitionTestError.failed))
        await waitUntil { viewModel.scanState == .failed(message: FishScannerViewModel.identificationFailedMessage) }

        XCTAssertEqual(viewModel.scanState, .failed(message: FishScannerViewModel.identificationFailedMessage))
    }

    func testUnprocessableImageYieldsFailedWithoutCallingIdentifier() async {
        let identifier = FishIdentifyingFake()
        let preparer = ImagePreparingFake()
        preparer.stubResult = .failure(.invalidImageData)
        let viewModel = makeViewModel(identifier: identifier, preparer: preparer)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .failed(message: FishScannerViewModel.imageNotProcessableMessage) }

        XCTAssertEqual(viewModel.scanState, .failed(message: FishScannerViewModel.imageNotProcessableMessage))
        XCTAssertTrue(identifier.receivedImageData.isEmpty, "Con imagen no comprimible no debe llamarse a FishIdentifying")
        XCTAssertEqual(preparer.receivedData, [rawImage])
    }

    func testCancelDuringIdentifyingReturnsToIdleAndDiscardsPendingResult() async {
        let identifier = SuspendedFishIdentifying()
        let viewModel = makeViewModel(identifier: identifier)
        let result = makeResult()

        viewModel.setImage(data: rawImage)
        await waitUntil { identifier.isSuspended }
        XCTAssertEqual(viewModel.scanState, .identifying)

        viewModel.cancelCapture()
        XCTAssertEqual(viewModel.scanState, .idle)

        identifier.release(result: .success(.identified(result)))
        await settle()

        XCTAssertEqual(
            viewModel.scanState,
            .idle,
            "El resultado de una identificación cancelada no debe aplicarse"
        )
    }

    func testCancelFromIdleKeepsIdle() {
        let viewModel = makeViewModel(identifier: FishIdentifyingFake())

        viewModel.cancelCapture()

        XCTAssertEqual(viewModel.scanState, .idle)
    }

    func testRetryWithAnotherPhotoFromNoMatchReturnsToIdle() async {
        let identifier = FishIdentifyingFake()
        identifier.stubResult = .success(.noMatch)
        let viewModel = makeViewModel(identifier: identifier)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .noMatch }

        viewModel.retryWithAnotherPhoto()

        XCTAssertEqual(viewModel.scanState, .idle)
    }

    func testRetryWithAnotherPhotoFromFailedReturnsToIdle() async {
        let identifier = FishIdentifyingFake()
        identifier.stubResult = .failure(RecognitionTestError.failed)
        let viewModel = makeViewModel(identifier: identifier)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .failed(message: FishScannerViewModel.identificationFailedMessage) }

        viewModel.retryWithAnotherPhoto()

        XCTAssertEqual(viewModel.scanState, .idle)
    }

    func testNewImageDuringIdentificationCancelsPreviousAndUsesLatest() async {
        let identifier = SuspendedFishIdentifying()
        let viewModel = makeViewModel(identifier: identifier)
        let firstResult = makeResult()
        let secondSpecies = Species(id: "species-bluegill", commonName: "Bluegill", scientificName: "Lepomis macrochirus")
        let secondResult = IdentificationResult(species: secondSpecies, certainty: 0.62, confidence: .reliable)

        viewModel.setImage(data: Data([0x01]))
        await waitUntil { identifier.isSuspended }

        viewModel.setImage(data: Data([0x02]))
        await waitUntil { identifier.callCount == 2 }

        identifier.release(result: .success(.identified(firstResult)))
        identifier.release(result: .success(.identified(secondResult)))
        await waitUntil { viewModel.scanState == .identified(secondResult) }

        XCTAssertEqual(
            viewModel.scanState,
            .identified(secondResult),
            "Debe ganar la identificación de la imagen más reciente"
        )
        XCTAssertEqual(identifier.cancelledCallCount, 1, "La identificación en curso anterior debe quedar cancelada")
    }

    func testLowConfidenceResultIsPresentedAsIdentified() async {
        let identifier = FishIdentifyingFake()
        let lowResult = IdentificationResult(
            species: makeSpecies(),
            certainty: 0.40,
            confidence: .low
        )
        identifier.stubResult = .success(.identified(lowResult))
        let viewModel = makeViewModel(identifier: identifier)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .identified(lowResult) }

        XCTAssertEqual(viewModel.scanState, .identified(lowResult))
    }

    func testSaveCapturedCatchSuccessTransitionsToSavedAndDeliversPreparedPhoto() async {
        let identifier = FishIdentifyingFake()
        let result = makeResult()
        identifier.stubResult = .success(.identified(result))
        let preparer = ImagePreparingFake()
        preparer.stubResult = .success(preparedImage)
        let saver = CatchSavingFake()
        saver.stubResult = .success(())
        let viewModel = makeViewModel(identifier: identifier, preparer: preparer, catchSaver: saver)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .identified(result) }

        await viewModel.saveCapturedCatch()
        await waitUntil { viewModel.saveState == .saved }

        XCTAssertEqual(viewModel.saveState, .saved)
        XCTAssertEqual(viewModel.scanState, .identified(result), "La especie debe conservarse en pantalla tras guardar")
        XCTAssertEqual(saver.receivedSpecies, [result.species], "CatchSaving debe recibir la especie identificada")
        XCTAssertEqual(
            saver.receivedPhotoData,
            [preparedImage],
            "CatchSaving debe recibir la foto comprimida, no la original"
        )
    }

    func testSaveCapturedCatchFailureTransitionsToSaveFailedAndAllowsRetry() async {
        let identifier = FishIdentifyingFake()
        let result = makeResult()
        identifier.stubResult = .success(.identified(result))
        let saver = CatchSavingFake()
        saver.stubResult = .failure(CatchSavingFakeError.saveFailed)
        let viewModel = makeViewModel(identifier: identifier, catchSaver: saver)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .identified(result) }

        await viewModel.saveCapturedCatch()
        await waitUntil { viewModel.saveState == .saveFailed }

        XCTAssertEqual(viewModel.saveState, .saveFailed)
        XCTAssertEqual(
            viewModel.scanState,
            .identified(result),
            "Tras un fallo de guardado la especie debe seguir en pantalla para poder reintentar"
        )
        XCTAssertEqual(saver.receivedSpecies, [result.species], "El fallo aun así debe entregar el draft")

        saver.stubResult = .success(())
        await viewModel.saveCapturedCatch()
        await waitUntil { viewModel.saveState == .saved }

        XCTAssertEqual(viewModel.saveState, .saved, "El reintento tras saveFailed debe poder guardar")
        XCTAssertEqual(saver.receivedSpecies.count, 2, "El reintento debe entregar el draft de nuevo")
    }

    func testSaveCapturedCatchWithoutIdentificationDoesNothing() async {
        let saver = CatchSavingFake()
        let viewModel = makeViewModel(identifier: FishIdentifyingFake(), catchSaver: saver)

        await viewModel.saveCapturedCatch()

        XCTAssertEqual(viewModel.saveState, .idle)
        XCTAssertTrue(saver.receivedSpecies.isEmpty, "Sin especie identificada no debe entregarse nada a CatchSaving")
        XCTAssertTrue(saver.receivedPhotoData.isEmpty)
    }

    func testSaveCapturedCatchFromNoMatchDoesNothing() async {
        let identifier = FishIdentifyingFake()
        identifier.stubResult = .success(.noMatch)
        let saver = CatchSavingFake()
        let viewModel = makeViewModel(identifier: identifier, catchSaver: saver)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .noMatch }

        await viewModel.saveCapturedCatch()

        XCTAssertEqual(viewModel.saveState, .idle)
        XCTAssertTrue(saver.receivedSpecies.isEmpty, "Sin coincidencia no puede guardarse captura")
    }

    func testSavingStateKeepsIdentifiedSpeciesOnScreen() async {
        let identifier = FishIdentifyingFake()
        let result = makeResult()
        identifier.stubResult = .success(.identified(result))
        let saver = SuspendedCatchSaving()
        let viewModel = makeViewModel(identifier: identifier, catchSaver: saver)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .identified(result) }

        let save = Task { await viewModel.saveCapturedCatch() }
        await waitUntil { viewModel.saveState == .saving && saver.isSuspended }

        XCTAssertEqual(viewModel.saveState, .saving)
        XCTAssertEqual(
            viewModel.scanState,
            .identified(result),
            "Durante el guardado la especie debe seguir identificada en pantalla"
        )

        saver.release(result: .success(()))
        await save.value
        await waitUntil { viewModel.saveState == .saved }

        XCTAssertEqual(viewModel.saveState, .saved)
    }

    func testNewScanResetsPriorSaveState() async {
        let identifier = FishIdentifyingFake()
        let result = makeResult()
        identifier.stubResult = .success(.identified(result))
        let saver = CatchSavingFake()
        saver.stubResult = .success(())
        let viewModel = makeViewModel(identifier: identifier, catchSaver: saver)

        viewModel.setImage(data: rawImage)
        await waitUntil { viewModel.scanState == .identified(result) }
        await viewModel.saveCapturedCatch()
        await waitUntil { viewModel.saveState == .saved }
        XCTAssertEqual(viewModel.saveState, .saved)

        viewModel.retryWithAnotherPhoto()

        XCTAssertEqual(viewModel.saveState, .idle, "Un nuevo escaneo debe reiniciar el estado de guardado")
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            await Task.yield()
        }
    }

    private func settle() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

private enum RecognitionTestError: Error, Equatable {
    case failed
}

private final class ImagePreparingFake: ImagePreparing, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(
        initialState: (stubResult: Result<Data, ImagePrepError>.success(Data()), received: [Data]())
    )

    var stubResult: Result<Data, ImagePrepError> {
        get { state.withLock { $0.stubResult } }
        set { state.withLock { $0.stubResult = newValue } }
    }

    var receivedData: [Data] {
        state.withLock { $0.received }
    }

    func prepare(_ data: Data) throws -> Data {
        try state.withLock { state in
            state.received.append(data)
            return try state.stubResult.get()
        }
    }
}

private final class SuspendedFishIdentifying: FishIdentifying, @unchecked Sendable {
    private struct State {
        var continuations: [CheckedContinuation<IdentificationOutcome, Error>] = []
        var callCount = 0
        var cancelledCallCount = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var isSuspended: Bool {
        lock.withLock { !$0.continuations.isEmpty }
    }

    var callCount: Int {
        lock.withLock { $0.callCount }
    }

    var cancelledCallCount: Int {
        lock.withLock { $0.cancelledCallCount }
    }

    func recognize(imageData: Data) async throws -> IdentificationOutcome {
        lock.withLock { state in
            state.callCount += 1
        }

        let outcome = try await withCheckedThrowingContinuation { continuation in
            lock.withLock { state in
                state.continuations.append(continuation)
            }
        }

        if Task.isCancelled {
            lock.withLock { state in
                state.cancelledCallCount += 1
            }
        }
        return outcome
    }

    func release(result: Result<IdentificationOutcome, Error>) {
        let continuation = lock.withLock { state -> CheckedContinuation<IdentificationOutcome, Error>? in
            guard !state.continuations.isEmpty else { return nil }
            return state.continuations.removeFirst()
        }
        guard let continuation else { return }

        switch result {
        case .success(let outcome):
            continuation.resume(returning: outcome)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private final class SuspendedCatchSaving: CatchSaving, @unchecked Sendable {
    private struct State {
        var continuations: [CheckedContinuation<Void, Error>] = []
        var callCount = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var isSuspended: Bool {
        lock.withLock { !$0.continuations.isEmpty }
    }

    var callCount: Int {
        lock.withLock { $0.callCount }
    }

    func saveDraft(species: Species, photoData: Data) async throws {
        lock.withLock { state in
            state.callCount += 1
        }
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { state in
                state.continuations.append(continuation)
            }
        }
    }

    func release(result: Result<Void, Error>) {
        let continuation = lock.withLock { state -> CheckedContinuation<Void, Error>? in
            guard !state.continuations.isEmpty else { return nil }
            return state.continuations.removeFirst()
        }
        guard let continuation else { return }

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}