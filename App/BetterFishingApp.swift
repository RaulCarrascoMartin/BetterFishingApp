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
    private let services: AppRootServices
    private let cameraManager: CameraManager
    private let gallerySelectionProvider: (@MainActor () -> Data?)?
    #if DEBUG
    private let detailScenario: CatchDetailScenario?
    private let logScenario: CatchLogScenario?
    #endif

    init(
        services: AppRootServices = AppComposition.makeRootServices(),
        cameraManager: CameraManager = AppComposition.makeCameraManager()
    ) {
        self.services = services
        self.cameraManager = cameraManager
        #if DEBUG
        self.gallerySelectionProvider = AppComposition.makeGallerySelectionProvider()
        self.detailScenario = AppComposition.makeCatchDetailScenario()
        self.logScenario = AppComposition.makeCatchLogScenario()
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
        } else if let logScenario {
            NavigationStack {
                CatchLogView(
                    viewModel: logScenario.viewModel,
                    thumbnailProvider: logScenario.thumbnailProvider,
                    detailViewModelFactory: logScenario.detailViewModelFactory
                )
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
                viewModel: services.scannerViewModel,
                cameraManager: cameraManager,
                gallerySelectionProvider: gallerySelectionProvider
            )
            #if DEBUG
            .task {
                guard UITestScenario.requested(in: ProcessInfo.processInfo.arguments) == nil else { return }
                try? await services.migrator.migrateIfNeeded()
            }
            #else
            .task {
                try? await services.migrator.migrateIfNeeded()
            }
            #endif
        }
    }
}

#Preview {
    RootView()
}