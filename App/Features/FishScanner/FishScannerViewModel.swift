import Foundation
import Observation

protocol ImagePreparing: Sendable {
    func prepare(_ data: Data) throws -> Data
}

struct DefaultImagePreparer: ImagePreparing {
    func prepare(_ data: Data) throws -> Data {
        try ImageCompressor.compress(data)
    }
}

@MainActor
@Observable
final class FishScannerViewModel {
    enum ScanState: Equatable {
        case idle
        case imageReady
        case identifying
        case identified(IdentificationResult)
        case noMatch
        case failed(message: String)
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case saveFailed
    }

    static let imageNotProcessableMessage = "No se pudo procesar la imagen"
    static let identificationFailedMessage = "No se pudo completar la identificación"

    private(set) var scanState: ScanState
    private(set) var saveState: SaveState

    private let identifier: any FishIdentifying
    private let imagePreparer: any ImagePreparing
    private let catchSaver: any CatchSaving
    private var pendingImage: Data?
    private var preparedPhotoData: Data?
    private var identificationGeneration = 0
    private var identificationTask: Task<Void, Never>?

    init(
        identifier: any FishIdentifying,
        imagePreparer: any ImagePreparing = DefaultImagePreparer(),
        catchSaver: any CatchSaving
    ) {
        self.identifier = identifier
        self.imagePreparer = imagePreparer
        self.catchSaver = catchSaver
        self.scanState = .idle
        self.saveState = .idle
    }

    func setImage(data: Data) {
        cancelInFlightIdentification()
        pendingImage = data
        preparedPhotoData = nil
        saveState = .idle
        scanState = .imageReady
        startIdentification()
    }

    func startIdentification() {
        guard scanState == .imageReady, identificationTask == nil else { return }
        scanState = .identifying
        identificationGeneration += 1
        let generation = identificationGeneration
        let imageData = pendingImage
        identificationTask = Task { [weak self] in
            await self?.performIdentification(imageData: imageData, generation: generation)
        }
    }

    func cancelCapture() {
        cancelInFlightIdentification()
        pendingImage = nil
        preparedPhotoData = nil
        saveState = .idle
        scanState = .idle
    }

    func retryWithAnotherPhoto() {
        cancelInFlightIdentification()
        pendingImage = nil
        preparedPhotoData = nil
        saveState = .idle
        scanState = .idle
    }

    func saveCapturedCatch() async {
        guard case .identified(let result) = scanState,
              let photoData = preparedPhotoData,
              saveState != .saving else {
            return
        }
        saveState = .saving
        do {
            try await catchSaver.saveDraft(species: result.species, photoData: photoData)
            saveState = .saved
        } catch {
            saveState = .saveFailed
        }
    }

    private func cancelInFlightIdentification() {
        identificationGeneration += 1
        identificationTask?.cancel()
        identificationTask = nil
    }

    private func performIdentification(imageData: Data?, generation: Int) async {
        defer {
            if generation == identificationGeneration {
                identificationTask = nil
            }
        }
        guard generation == identificationGeneration, let imageData else {
            return
        }

        let prepared: Data
        do {
            prepared = try imagePreparer.prepare(imageData)
        } catch {
            guard generation == identificationGeneration else { return }
            scanState = .failed(message: Self.imageNotProcessableMessage)
            return
        }
        guard generation == identificationGeneration else { return }

        let outcome: IdentificationOutcome
        do {
            outcome = try await identifier.recognize(imageData: prepared)
        } catch {
            guard generation == identificationGeneration else { return }
            scanState = .failed(message: Self.identificationFailedMessage)
            return
        }

        guard generation == identificationGeneration else { return }
        switch outcome {
        case .identified(let result):
            preparedPhotoData = prepared
            scanState = .identified(result)
        case .noMatch:
            preparedPhotoData = nil
            scanState = .noMatch
        }
    }
}