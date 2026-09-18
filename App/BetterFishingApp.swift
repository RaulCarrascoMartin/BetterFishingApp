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

    init(
        viewModel: FishScannerViewModel = AppComposition.makeScannerViewModel(),
        cameraManager: CameraManager = AppComposition.makeCameraManager()
    ) {
        self.viewModel = viewModel
        self.cameraManager = cameraManager
    }

    var body: some View {
        NavigationStack {
            FishScannerView(viewModel: viewModel, cameraManager: cameraManager)
        }
    }
}

#Preview {
    RootView()
}