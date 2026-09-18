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
    case detailLoaded
    case detailDeleteFails
    case logLoading
    case logLoaded
    case logEmpty

    var isDetail: Bool {
        switch self {
        case .detailLoaded, .detailDeleteFails: return true
        default: return false
        }
    }

    var isLog: Bool {
        switch self {
        case .logLoading, .logLoaded, .logEmpty: return true
        default: return false
        }
    }

    static func requested(in arguments: [String]) -> UITestScenario? {
        guard let index = arguments.firstIndex(of: "--ui-test-double"),
              arguments.indices.contains(index + 1),
              let scenario = UITestScenario(rawValue: arguments[index + 1]) else {
            return nil
        }
        return scenario
    }
}

struct CatchDetailScenario {
    let id: UUID
    let viewModel: CatchDetailViewModel
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
        case .noMatch, .detailLoaded, .detailDeleteFails, .logLoading, .logLoaded, .logEmpty:
            return .noMatch
        }
    }
}

@MainActor
extension AppComposition {
    static func makeCatchDetailScenario(arguments: [String] = ProcessInfo.processInfo.arguments) -> CatchDetailScenario? {
        guard let scenario = UITestScenario.requested(in: arguments), scenario.isDetail else { return nil }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestDetail-\(UUID().uuidString)", isDirectory: true)
        let repository = LocalFileCatchRepository(directoryURL: directoryURL)
        UITestDetailFixture.seed(into: repository, at: directoryURL)

        let detailRepository: any CatchRepository
        if scenario == .detailDeleteFails {
            detailRepository = UITestDoubleDetailRepository(real: repository, failuresBeforeSuccess: 1)
        } else {
            detailRepository = repository
        }

        let viewModel = CatchDetailViewModel(
            id: UITestDetailFixture.id,
            repository: detailRepository,
            photoProvider: { repository.photoData(for: $0) }
        )
        return CatchDetailScenario(id: UITestDetailFixture.id, viewModel: viewModel)
    }

    static func makeCatchLogScenario(arguments: [String] = ProcessInfo.processInfo.arguments) -> CatchLogScenario? {
        guard let scenario = UITestScenario.requested(in: arguments), scenario.isLog else { return nil }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestLog-\(UUID().uuidString)", isDirectory: true)
        let repository = LocalFileCatchRepository(directoryURL: directoryURL)

        if scenario == .logLoaded {
            UITestLogFixture.seed(into: repository)
        }

        let viewModel = CatchLogViewModel(repository: repository)
        return CatchLogScenario(
            viewModel: viewModel,
            thumbnailProvider: { repository.photoData(for: $0) },
            detailViewModelFactory: { catchEntry in
                CatchDetailViewModel(
                    id: catchEntry.id,
                    repository: repository,
                    photoProvider: { repository.photoData(for: $0) }
                )
            }
        )
    }
}

struct CatchLogScenario {
    let viewModel: CatchLogViewModel
    let thumbnailProvider: (Catch) -> Data?
    let detailViewModelFactory: @MainActor (Catch) -> CatchDetailViewModel
}

enum UITestLogFixture {
    static let bassDate = Date(timeIntervalSince1970: 1_751_653_800)
    static let bluegillDate = Date(timeIntervalSince1970: 1_750_000_000)

    static func seed(into repository: LocalFileCatchRepository) {
        let photoData = UITestImageFixture.makeJPEGData()
        let entries: [(species: Species, date: Date, notes: String)] = [
            (UITestScenarios.reliableBass.species, bassDate, "Registrada desde el escáner"),
            (UITestScenarios.lowConfidenceBluegill.species, bluegillDate, "Pequeño ejemplar de primavera"),
        ]

        let semaphore = DispatchSemaphore(value: 0)
        let savedCount = SavedCount()
        Task.detached {
            defer { semaphore.signal() }
            for entry in entries {
                if let saved = try? await repository.saveCatch(
                    species: entry.species,
                    photoData: photoData,
                    date: entry.date,
                    location: nil,
                    notes: entry.notes
                ) {
                    savedCount.value += 1
                }
            }
        }
        _ = semaphore.wait(timeout: .now() + 15)

        guard savedCount.value == entries.count else {
            assertionFailure("No se pudieron sembrar los fixtures de capturas del log")
            return
        }
    }

    private final class SavedCount: @unchecked Sendable {
        var value = 0
    }
}

enum UITestDetailFixture {
    // Fuerza de desencriptación solo del UUID fijo del fixture de UI test (constante conocida).
    static let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!
    static let date = Date(timeIntervalSince1970: 1_751_653_800)
    static let location = LocationCoordinate2D(latitude: 41.4038, longitude: 2.1741)
    static let notes = "Captura de prueba"
    static let species = UITestScenarios.reliableBass.species

    static func seed(into repository: LocalFileCatchRepository, at directoryURL: URL) {
        let photoData = UITestImageFixture.makeJPEGData()
        let semaphore = DispatchSemaphore(value: 0)
        let result = SeedResult()
        Task.detached {
            defer { semaphore.signal() }
            result.catchEntry = try? await repository.saveCatch(
                species: species,
                photoData: photoData,
                date: date,
                location: location,
                notes: notes
            )
        }
        _ = semaphore.wait(timeout: .now() + 15)

        guard let saved = result.catchEntry else {
            assertionFailure("No se pudo sembrar la captura de fixture en el repositorio real")
            return
        }
        reroot(saved: saved, at: directoryURL)
    }

    // saveCatch genera su propio UUID: se reescribe el metadato bajo el UUID fijo del fixture
    // para que getCatch(id: UITestDetailFixture.id) resuelva el catch sembrado.
    private static func reroot(saved: Catch, at directoryURL: URL) {
        let manager = FileManager.default
        let fixed = Catch(
            id: id,
            species: saved.species,
            photoPath: "\(id.uuidString).jpg",
            date: saved.date,
            location: saved.location,
            notes: saved.notes,
            createdAt: saved.createdAt
        )
        do {
            try manager.removeItem(at: directoryURL.appendingPathComponent("\(saved.id.uuidString).json"))
            try manager.moveItem(
                at: directoryURL.appendingPathComponent(saved.photoPath),
                to: directoryURL.appendingPathComponent("\(id.uuidString).jpg")
            )
            try JSONEncoder().encode(fixed).write(
                to: directoryURL.appendingPathComponent("\(id.uuidString).json"),
                options: .atomic
            )
        } catch {
            assertionFailure("No se pudo fijar el UUID del fixture: \(error)")
        }
    }

    private final class SeedResult: @unchecked Sendable {
        var catchEntry: Catch?
    }
}

actor UITestDoubleDetailRepository: CatchRepository {
    private let real: any CatchRepository
    private var remainingDeleteFailures: Int

    init(real: any CatchRepository, failuresBeforeSuccess: Int = 1) {
        self.real = real
        self.remainingDeleteFailures = failuresBeforeSuccess
    }

    func saveCatch(species: Species, photoData: Data, date: Date, location: LocationCoordinate2D?, notes: String) async throws -> Catch {
        try await real.saveCatch(species: species, photoData: photoData, date: date, location: location, notes: notes)
    }

    func listCatches() async throws -> [Catch] {
        try await real.listCatches()
    }

    func getCatch(id: UUID) async throws -> Catch? {
        try await real.getCatch(id: id)
    }

    func updateCatch(id: UUID, date: Date?, location: LocationCoordinate2D?, notes: String?) async throws {
        try await real.updateCatch(id: id, date: date, location: location, notes: notes)
    }

    func deleteCatch(id: UUID) async throws {
        if remainingDeleteFailures > 0 {
            remainingDeleteFailures -= 1
            throw CatchSaveError.writeFailed
        }
        try await real.deleteCatch(id: id)
    }
}

actor UITestDoubleCatchSaver: CatchSaving {
    let scenario: UITestScenario
    private var remainingFailures: Int

    init(scenario: UITestScenario, failuresBeforeSuccess: Int = 1) {
        self.scenario = scenario
        self.remainingFailures = failuresBeforeSuccess
    }

    func saveDraft(species: Species, photoData: Data) async throws {
        guard scenario == .saveFails, remainingFailures > 0 else { return }
        remainingFailures -= 1
        throw UITestCatchSaveError.failed
    }
}

private enum UITestCatchSaveError: Error {
    case failed
}
#endif