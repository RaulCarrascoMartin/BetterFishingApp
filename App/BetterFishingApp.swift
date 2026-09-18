import SwiftUI

@main
struct BetterFishingApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

@MainActor
struct RootView: View {
    private let viewModel: FishScannerViewModel
    private let cameraManager: CameraManager
    private let gallerySelectionProvider: (@MainActor () -> Data?)?

    init(
        viewModel: FishScannerViewModel = AppComposition.makeScannerViewModel(),
        cameraManager: CameraManager = AppComposition.makeCameraManager()
    ) {
        self.viewModel = viewModel
        self.cameraManager = cameraManager
        #if DEBUG
        self.gallerySelectionProvider = AppComposition.makeGallerySelectionProvider()
        #else
        self.gallerySelectionProvider = nil
        #endif
    }

    var body: some View {
        NavigationStack {
            FishScannerView(
                viewModel: viewModel,
                cameraManager: cameraManager,
                gallerySelectionProvider: gallerySelectionProvider
            )
        }
    }
}

#Preview {
    RootView()
}