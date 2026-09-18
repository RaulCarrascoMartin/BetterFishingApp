#if DEBUG
import Foundation
import SwiftUI

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
        makeViewModel(state: state, catchSaver: PreviewCatchSaver())
    }

    static func makeViewModel(
        state: FishScannerViewModel.ScanState,
        catchSaver: any CatchSaving
    ) -> FishScannerViewModel {
        let viewModel: FishScannerViewModel
        switch state {
        case .identifying:
            viewModel = FishScannerViewModel(
                identifier: PendingPreviewFishIdentifier(),
                imagePreparer: PreviewPassthroughImagePreparer(),
                catchSaver: catchSaver
            )
        case .failed:
            viewModel = FishScannerViewModel(
                identifier: ThrowingPreviewFishIdentifier(),
                imagePreparer: PreviewPassthroughImagePreparer(),
                catchSaver: catchSaver
            )
        case .identified(let result):
            viewModel = FishScannerViewModel(
                identifier: PreviewFishIdentifier(outcome: .identified(result)),
                imagePreparer: PreviewPassthroughImagePreparer(),
                catchSaver: catchSaver
            )
        case .idle, .imageReady, .noMatch:
            viewModel = FishScannerViewModel(
                identifier: PreviewFishIdentifier(outcome: .noMatch),
                imagePreparer: PreviewPassthroughImagePreparer(),
                catchSaver: catchSaver
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

@MainActor
struct SaveStatePreviewView: View {
    private let viewModel: FishScannerViewModel

    init(target: FishScannerViewModel.SaveState) {
        let saver: any CatchSaving
        switch target {
        case .saving:
            saver = PendingPreviewCatchSaver()
        case .saveFailed:
            saver = FailingPreviewCatchSaver()
        case .saved:
            saver = PreviewCatchSaver()
        case .idle:
            saver = PreviewCatchSaver()
        }
        self.viewModel = FishScannerPreviewSupport.makeViewModel(
            state: .identified(FishScannerPreviewSupport.reliableBass),
            catchSaver: saver
        )
    }

    var body: some View {
        NavigationStack {
            FishScannerView(viewModel: viewModel)
                .task {
                    for _ in 0..<100 where viewModel.scanState != .identified(FishScannerPreviewSupport.reliableBass) {
                        try? await Task.sleep(for: .milliseconds(20))
                    }
                    guard case .identified = viewModel.scanState else { return }
                    await viewModel.saveCapturedCatch()
                }
        }
    }
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

private struct PendingPreviewCatchSaver: CatchSaving {
    func saveDraft(species: Species, photoData: Data) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

private struct FailingPreviewCatchSaver: CatchSaving {
    struct PreviewSaveError: Error {}
    func saveDraft(species: Species, photoData: Data) async throws {
        throw PreviewSaveError()
    }
}
#endif