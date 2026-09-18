import Foundation

struct FishialCredentials: Equatable {
    let clientID: String
    let clientSecret: String

    init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    init(bundle: Bundle = .main) {
        self.clientID = bundle.object(forInfoDictionaryKey: "FishialClientID") as? String ?? ""
        self.clientSecret = bundle.object(forInfoDictionaryKey: "FishialClientSecret") as? String ?? ""
    }
}

enum AppComposition {
    @MainActor
    static func makeScannerViewModel(
        credentials: FishialCredentials = FishialCredentials(bundle: .main),
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> FishScannerViewModel {
        let identifier: any FishIdentifying
        let catchSaver: any CatchSaving
        #if DEBUG
        if let scenario = UITestScenario.requested(in: arguments) {
            (identifier, catchSaver) = makeUITestDoubles(scenario: scenario)
        } else {
            (identifier, catchSaver) = makeProductionServices(credentials: credentials)
        }
        #else
        (identifier, catchSaver) = makeProductionServices(credentials: credentials)
        #endif
        return FishScannerViewModel(identifier: identifier, catchSaver: catchSaver)
    }

    @MainActor
    static func makeCameraManager(arguments: [String] = ProcessInfo.processInfo.arguments) -> CameraManager {
        #if DEBUG
        if UITestScenario.requested(in: arguments) != nil {
            let device = UITestCameraDevice()
            return CameraManager(authorization: UITestCameraAuthorization(), session: device, photoOutput: device)
        }
        #endif
        return CameraManager()
    }

    #if DEBUG
    @MainActor
    static func makeGallerySelectionProvider(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> (@MainActor () -> Data?)? {
        guard UITestScenario.requested(in: arguments) != nil else { return nil }
        return { UITestImageFixture.makeJPEGData() }
    }
    #endif

    private static func makeProductionServices(
        credentials: FishialCredentials
    ) -> (any FishIdentifying, any CatchSaving) {
        let tokenStore = FishialTokenStore(
            clientID: credentials.clientID,
            clientSecret: credentials.clientSecret
        )
        return (FishialClient(tokenStore: tokenStore), LocalDraftCatchSaver())
    }
}

#if DEBUG
enum UITestScenario: String {
    case identifiedReliable
    case identifiedLowConfidence
    case noMatch
    case saveSucceeds
    case saveFails

    static func requested(in arguments: [String]) -> UITestScenario? {
        guard let index = arguments.firstIndex(of: "--ui-test-double"),
              arguments.indices.contains(index + 1),
              let scenario = UITestScenario(rawValue: arguments[index + 1]) else {
            return nil
        }
        return scenario
    }
}

enum UITestScenarios {
    static let reliableBass = IdentificationResult(
        species: Species(
            id: "uitest-reliable",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        ),
        certainty: 0.92,
        confidence: .reliable
    )

    static let lowConfidenceBluegill = IdentificationResult(
        species: Species(
            id: "uitest-low-confidence",
            commonName: "Bluegill",
            scientificName: "Lepomis macrochirus"
        ),
        certainty: 0.41,
        confidence: .low
    )
}

private func makeUITestDoubles(scenario: UITestScenario) -> (any FishIdentifying, any CatchSaving) {
    (UITestDoubleFishIdentifier(scenario: scenario), UITestDoubleCatchSaver(scenario: scenario))
}

struct UITestDoubleFishIdentifier: FishIdentifying {
    let scenario: UITestScenario

    func recognize(imageData: Data) async throws -> IdentificationOutcome {
        try await Task.sleep(for: .milliseconds(3000))
        switch scenario {
        case .identifiedReliable, .saveSucceeds, .saveFails:
            return .identified(UITestScenarios.reliableBass)
        case .identifiedLowConfidence:
            return .identified(UITestScenarios.lowConfidenceBluegill)
        case .noMatch:
            return .noMatch
        }
    }
}

struct UITestDoubleCatchSaver: CatchSaving {
    let scenario: UITestScenario

    func saveDraft(species: Species, photoData: Data) async throws {
        if scenario == .saveFails {
            throw UITestCatchSaveError.failed
        }
    }
}

private enum UITestCatchSaveError: Error {
    case failed
}
#endif