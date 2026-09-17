#if DEBUG
import Foundation

@MainActor
enum FishScannerPreviewSupport {
    static let reliableBass = IdentificationResult(
        species: Species(
            id: "preview-bass",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        ),
        certainty: 0.91,
        confidence: .reliable
    )

    static let lowConfidenceBluegill = IdentificationResult(
        species: Species(
            id: "preview-bluegill",
            commonName: "Bluegill",
            scientificName: "Lepomis macrochirus"
        ),
        certainty: 0.41,
        confidence: .low
    )

    static func makeViewModel(state: FishScannerViewModel.ScanState) -> FishScannerViewModel {
        let viewModel: FishScannerViewModel
        switch state {
        case .identifying:
            viewModel = FishScannerViewModel(
                identifier: PendingPreviewFishIdentifier(),
                imagePreparer: PreviewPassthroughImagePreparer(),
                catchSaver: PreviewCatchSaver()
            )
        case .failed:
            viewModel = FishScannerViewModel(
                identifier: ThrowingPreviewFishIdentifier(),
                imagePreparer: PreviewPassthroughImagePreparer(),
                catchSaver: PreviewCatchSaver()
            )
        case .identified(let result):
            viewModel = FishScannerViewModel(
                identifier: PreviewFishIdentifier(outcome: .identified(result)),
                imagePreparer: PreviewPassthroughImagePreparer(),
                catchSaver: PreviewCatchSaver()
            )
        case .idle, .imageReady, .noMatch:
            viewModel = FishScannerViewModel(
                identifier: PreviewFishIdentifier(outcome: .noMatch),
                imagePreparer: PreviewPassthroughImagePreparer(),
                catchSaver: PreviewCatchSaver()
            )
        }

        switch state {
        case .idle, .imageReady:
            return viewModel
        case .identifying, .identified, .noMatch, .failed:
            viewModel.setImage(data: previewJPEGData)
            return viewModel
        }
    }

    private static let previewJPEGData = Data([0xFF, 0xD8, 0xFF, 0xE0])
}

private struct PreviewFishIdentifier: FishIdentifying {
    let outcome: IdentificationOutcome
    func recognize(imageData: Data) async throws -> IdentificationOutcome {
        outcome
    }
}

private struct PendingPreviewFishIdentifier: FishIdentifying {
    func recognize(imageData: Data) async throws -> IdentificationOutcome {
        await withCheckedContinuation { (_: CheckedContinuation<IdentificationOutcome, Never>) in }
    }
}

private struct ThrowingPreviewFishIdentifier: FishIdentifying {
    struct PreviewError: Error {}
    func recognize(imageData: Data) async throws -> IdentificationOutcome {
        throw PreviewError()
    }
}

private struct PreviewPassthroughImagePreparer: ImagePreparing {
    func prepare(_ data: Data) throws -> Data {
        data
    }
}

private struct PreviewCatchSaver: CatchSaving {
    func saveDraft(species: Species, photoData: Data) async throws {}
}
#endif