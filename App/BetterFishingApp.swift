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
    #if DEBUG
    private let detailScenario: CatchDetailScenario?
    #endif

    init(
        viewModel: FishScannerViewModel = AppComposition.makeScannerViewModel(),
        cameraManager: CameraManager = AppComposition.makeCameraManager()
    ) {
        self.viewModel = viewModel
        self.cameraManager = cameraManager
        #if DEBUG
        self.gallerySelectionProvider = AppComposition.makeGallerySelectionProvider()
        self.detailScenario = AppComposition.makeCatchDetailScenario()
        #else
        self.gallerySelectionProvider = nil
        #endif
    }

    var body: some View {
        #if DEBUG
        if let detailScenario {
            NavigationStack {
                CatchDetailView(viewModel: detailScenario.viewModel)
            }
        } else {
            scannerNavigation
        }
        #else
        scannerNavigation
        #endif
    }

    private var scannerNavigation: some View {
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