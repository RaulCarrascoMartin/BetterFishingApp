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

    init(viewModel: FishScannerViewModel = AppComposition.makeScannerViewModel()) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            FishScannerView(viewModel: viewModel)
        }
    }
}

#Preview {
    RootView()
}