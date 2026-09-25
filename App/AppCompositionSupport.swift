import Foundation
import os
import Supabase

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

@MainActor
struct AppRootServices {
    let scannerViewModel: FishScannerViewModel
    let catchSaver: any CatchSaving
    let catchLogViewModel: CatchLogViewModel
    let thumbnailProvider: @MainActor (Catch) -> Data?
    let detailViewModelFactory: @MainActor (Catch) -> CatchDetailViewModel
    let migrator: ProvisionalDraftsMigrator
    let supabase: SupabaseStack?
    let spotRepository: (any SpotRepository)?
    let spotMapViewModel: SpotMapViewModel?
    let spotDetailViewModelFactory: (@MainActor (Spot) -> SpotDetailViewModel)?
    let accountViewModel: AccountViewModel?
}

enum AppComposition {
    @MainActor
    static func makeRootServices(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        repository: LocalFileCatchRepository? = nil,
        draftsDirectory: URL? = nil,
        supabaseConfiguration: SupabaseClientConfiguration? = nil,
        supabaseOptions: SupabaseClientOptions? = nil,
        supabaseStack: SupabaseStack? = nil
    ) -> AppRootServices {
        #if DEBUG
        if let services = makeUITestRootServices(arguments: arguments, draftsDirectory: draftsDirectory) {
            return services
        }
        #endif

        let deviceLocationProvider = DeviceLocationProvider(
            authorization: CLLocationAuthorization(),
            fetcher: CLLocationFetcher()
        )
        let realRepository = repository ?? LocalFileCatchRepository(deviceLocationProvider: deviceLocationProvider)

        let credentials = FishialCredentials(bundle: .main)
        let tokenStore = FishialTokenStore(
            clientID: credentials.clientID,
            clientSecret: credentials.clientSecret
        )

        let supabase = supabaseStack ?? makeSupabaseStack(configuration: supabaseConfiguration, options: supabaseOptions)

        let spotRepository: (any SpotRepository)?
        let spotMapViewModel: SpotMapViewModel?
        let spotDetailViewModelFactory: (@MainActor (Spot) -> SpotDetailViewModel)?
        let accountViewModel: AccountViewModel?
        if let stack = supabase {
            let supabaseSpotRepository = SupabaseSpotRepository(database: stack.database, auth: stack.auth)
            spotRepository = supabaseSpotRepository
            spotMapViewModel = SpotMapViewModel(
                repository: supabaseSpotRepository,
                locationProvider: deviceLocationProvider,
                auth: stack.auth
            )
            spotDetailViewModelFactory = { spot in
                SpotDetailViewModel(
                    repository: supabaseSpotRepository,
                    auth: stack.auth,
                    spot: spot
                )
            }
            spotsLogger.info("Spots conectados sobre el stack de Supabase: repositorio y mapa construidos")

            let baseDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            let catchDirectory = baseDirectory.appendingPathComponent("Catches", isDirectory: true)
            let syncStore = FileSyncCatchStore(directoryURL: catchDirectory)
            let syncLedger = CatchSyncLedger(directoryURL: baseDirectory.appendingPathComponent("CatchSync", isDirectory: true))
            let catchSyncService = CatchSyncService(
                repository: realRepository,
                photoDataProvider: { realRepository.photoData(for: $0) },
                localStore: syncStore,
                ledger: syncLedger,
                database: stack.database,
                storage: stack.storage
            )
            let accountSessionManager = AccountSessionManager(auth: stack.auth)
            let profileRepository = SupabaseProfileRepository(
                auth: stack.auth,
                database: stack.database,
                storage: stack.storage
            )
            let favoritesPresenting = SpotRepositorySpotPresenting(repository: supabaseSpotRepository)
            accountViewModel = AccountViewModel(
                auth: accountSessionManager,
                profile: profileRepository,
                favorites: favoritesPresenting,
                sync: catchSyncService
            )
            accountLogger.info("Cuenta conectada sobre el stack de Supabase: sesión, perfil, favoritos y sincronización construidos")
        } else {
            spotsLogger.info("Sin capa de datos de Supabase: el repositorio de spots y la pestaña Mapa quedan en nil (degradación, Req 2)")
            accountLogger.info("Sin capa de datos de Supabase: la sección de cuenta queda en nil (degradación, Req 6.1)")
            spotRepository = nil
            spotMapViewModel = nil
            spotDetailViewModelFactory = nil
            accountViewModel = nil
        }

        return AppRootServices(
            scannerViewModel: FishScannerViewModel(
                identifier: FishialClient(tokenStore: tokenStore),
                catchSaver: realRepository
            ),
            catchSaver: realRepository,
            catchLogViewModel: CatchLogViewModel(repository: realRepository),
            thumbnailProvider: { realRepository.photoData(for: $0) },
            detailViewModelFactory: { catchEntry in
                CatchDetailViewModel(
                    id: catchEntry.id,
                    repository: realRepository,
                    photoProvider: { realRepository.photoData(for: $0) }
                )
            },
            migrator: ProvisionalDraftsMigrator(catchRepository: realRepository, draftsDirectory: draftsDirectory),
            supabase: supabase,
            spotRepository: spotRepository,
            spotMapViewModel: spotMapViewModel,
            spotDetailViewModelFactory: spotDetailViewModelFactory,
            accountViewModel: accountViewModel
        )
    }

    private static func makeSupabaseStack(
        configuration: SupabaseClientConfiguration?,
        options: SupabaseClientOptions?
    ) -> SupabaseStack? {
        let resolved = configuration ?? SupabaseClientConfiguration(bundle: .main)
        guard let resolved else {
            supabaseLogger.error("Configuración de Supabase ausente o inválida: el stack queda en nil")
            return nil
        }
        do {
            let stack = try SupabaseClientProvider(configuration: resolved).makeStack(options: options)
            supabaseLogger.info("Stack de Supabase construido: auth, storage y database disponibles")
            return stack
        } catch {
            supabaseLogger.error("No se pudo construir el stack de Supabase: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static let supabaseLogger = Logger(subsystem: "BetterFishing", category: "Supabase")
    private static let spotsLogger = Logger(subsystem: "BetterFishing", category: "Spots")
    private static let accountLogger = Logger(subsystem: "BetterFishing", category: "Account")

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
    static func makeUITestRootServices(
        arguments: [String],
        draftsDirectory: URL?
    ) -> AppRootServices? {
        guard let scenario = UITestScenario.requested(in: arguments), scenario.isScannerDriving || scenario.isMapSeeded || scenario.isAccount else {
            return nil
        }

        let identifier = UITestDoubleFishIdentifier(scenario: scenario)

        let catchSaver: any CatchSaving
        let repository: LocalFileCatchRepository
        var fixedDraftsDirectory: URL?

        switch scenario {
        case .registrySaveSucceeds, .registrySaveFailsRetry, .registryLogSeeded, .registryLogDeleteFails:
            repository = LocalFileCatchRepository(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("UITestRegistry-\(UUID().uuidString)", isDirectory: true),
                deviceLocationProvider: UITestNoLocationProvider()
            )
            if scenario == .registryLogSeeded || scenario == .registryLogDeleteFails {
                UITestLogFixture.seed(into: repository)
                catchSaver = repository
            } else if scenario == .registrySaveSucceeds {
                catchSaver = repository
            } else {
                catchSaver = UITestDoubleCatchSaver(scenario: scenario, inner: repository)
            }
        case .migrationLaunch1, .migrationLaunch2:
            let suffix = UITestPersistenceArgument.suffix(in: arguments)
            let registryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("UITestRegistry-\(suffix)", isDirectory: true)
            let draftsURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("UITestDrafts-\(suffix)", isDirectory: true)
            fixedDraftsDirectory = draftsURL
            repository = LocalFileCatchRepository(
                directoryURL: registryURL,
                deviceLocationProvider: UITestNoLocationProvider()
            )
            if scenario.seedsLegacyDrafts {
                UITestLegacyDraftFixture.seedDraft(into: draftsURL, date: UITestLogFixture.bassDate)
            }
            catchSaver = repository
        case .spotMapSeeded:
            repository = LocalFileCatchRepository(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("UITestSpotMap-\(UUID().uuidString)", isDirectory: true),
                deviceLocationProvider: UITestNoLocationProvider()
            )
            catchSaver = repository
        default:
            repository = LocalFileCatchRepository(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("UITestRoot-\(UUID().uuidString)", isDirectory: true)
            )
            catchSaver = UITestDoubleCatchSaver(scenario: scenario)
        }

        let detailRepository: any CatchRepository
        if scenario == .registryLogDeleteFails {
            detailRepository = UITestDoubleDetailRepository(real: repository, failuresBeforeSuccess: 1)
        } else {
            detailRepository = repository
        }

        let spotRepository: (any SpotRepository)?
        let spotMapViewModel: SpotMapViewModel?
        let spotDetailViewModelFactory: (@MainActor (Spot) -> SpotDetailViewModel)?
        if scenario.isMapSeeded {
            let seededRepository = UITestSpotRepository.seededSpots
            spotRepository = seededRepository
            spotMapViewModel = SpotMapViewModel(
                repository: seededRepository,
                locationProvider: UITestNoLocationProvider(),
                auth: UITestNoAuthProvider()
            )
            spotDetailViewModelFactory = { spot in
                SpotDetailViewModel(
                    repository: seededRepository,
                    auth: UITestNoAuthProvider(),
                    spot: spot
                )
            }
        } else {
            spotRepository = nil
            spotMapViewModel = nil
            spotDetailViewModelFactory = nil
        }

        let accountViewModel: AccountViewModel?
        if scenario == .accountSignedIn {
            let user = UITestSignedInAuthProvider.user
            accountViewModel = AccountViewModel(
                auth: AccountSessionManager(auth: UITestSignedInAuthProvider()),
                profile: UITestAccountProfile(
                    profileValue: AccountProfile(
                        userID: user.id,
                        displayName: "Pescador de prueba",
                        avatarPath: nil
                    )
                ),
                favorites: UITestAccountFavorites(
                    favoritesValue: [
                        FavoriteSpot(
                            spotID: UITestSpotRepository.seededSpots.spots[0].id,
                            name: "Embalse de Sau",
                            category: "lake"
                        )
                    ]
                ),
                sync: UITestAccountSync(
                    result: CatchSyncResult(pushed: 1, pulled: 2, skipped: 3)
                )
            )
        } else if scenario.isAccount {
            accountViewModel = AccountViewModel(
                auth: AccountSessionManager(auth: UITestNoAuthProvider()),
                profile: UITestAccountProfile(),
                favorites: UITestAccountFavorites(),
                sync: UITestAccountSync()
            )
        } else {
            accountViewModel = nil
        }

        return AppRootServices(
            scannerViewModel: FishScannerViewModel(identifier: identifier, catchSaver: catchSaver),
            catchSaver: catchSaver,
            catchLogViewModel: CatchLogViewModel(repository: repository),
            thumbnailProvider: { repository.photoData(for: $0) },
            detailViewModelFactory: { catchEntry in
                CatchDetailViewModel(
                    id: catchEntry.id,
                    repository: detailRepository,
                    photoProvider: { repository.photoData(for: $0) }
                )
            },
            migrator: ProvisionalDraftsMigrator(
                catchRepository: repository,
                draftsDirectory: fixedDraftsDirectory ?? draftsDirectory
            ),
            supabase: nil,
            spotRepository: spotRepository,
            spotMapViewModel: spotMapViewModel,
            spotDetailViewModelFactory: spotDetailViewModelFactory,
            accountViewModel: accountViewModel
        )
    }
    #endif

    #if DEBUG
    @MainActor
    static func makeGallerySelectionProvider(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> (@MainActor () -> Data?)? {
        guard UITestScenario.requested(in: arguments) != nil else { return nil }
        return { UITestImageFixture.makeJPEGData() }
    }
    #endif
}

#if DEBUG
enum UITestScenario: String {
    case identifiedReliable
    case identifiedLowConfidence
    case noMatch
    case saveSucceeds
    case saveFails
    case registrySaveSucceeds
    case registrySaveFailsRetry
    case registryLogSeeded
    case registryLogDeleteFails
    case migrationLaunch1
    case migrationLaunch2
    case detailLoaded
    case detailDeleteFails
    case logLoading
    case logLoaded
    case logEmpty
    case spotMapSeeded
    case accountSignedOut
    case accountSignedIn

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

    var isScannerDriving: Bool {
        switch self {
        case .identifiedReliable, .identifiedLowConfidence, .noMatch, .saveSucceeds, .saveFails,
             .registrySaveSucceeds, .registrySaveFailsRetry, .registryLogSeeded, .registryLogDeleteFails,
             .migrationLaunch1, .migrationLaunch2:
            return true
        case .detailLoaded, .detailDeleteFails, .logLoading, .logLoaded, .logEmpty, .spotMapSeeded,
             .accountSignedOut, .accountSignedIn:
            return false
        }
    }

    var isAccount: Bool {
        self == .accountSignedOut || self == .accountSignedIn
    }

    var isMapSeeded: Bool {
        self == .spotMapSeeded
    }

    var seedsLegacyDrafts: Bool {
        self == .migrationLaunch1
    }

    var allowsLaunchMigration: Bool {
        switch self {
        case .migrationLaunch1, .migrationLaunch2: return true
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

enum UITestPersistenceArgument {
    static func suffix(in arguments: [String]) -> String {
        guard let index = arguments.firstIndex(of: "--ui-persistence"),
              arguments.indices.contains(index + 1),
              !arguments[index + 1].isEmpty else {
            return UUID().uuidString
        }
        return arguments[index + 1]
    }
}

enum UITestLegacyDraftFixture {
    static func seedDraft(
        into draftsDirectory: URL,
        species: Species = UITestScenarios.reliableBass.species,
        date: Date
    ) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)

        let draft = CatchDraft(
            id: UUID(),
            species: species,
            photoPath: "provisional.png",
            createdAt: date,
            status: .draft
        )
        do {
            try JSONEncoder()
                .encode(draft)
                .write(to: draftsDirectory.appendingPathComponent("metadata.json"), options: .atomic)
            try UITestImageFixture.makeJPEGData()
                .write(to: draftsDirectory.appendingPathComponent("provisional.png"), options: .atomic)
        } catch {
            assertionFailure("No se pudo sembrar el borrador provisional legacy: \(error)")
        }
    }
}

struct UITestDoubleFishIdentifier: FishIdentifying {
    let scenario: UITestScenario

    func recognize(imageData: Data) async throws -> IdentificationOutcome {
        try await Task.sleep(for: .milliseconds(3000))
        switch scenario {
        case .identifiedReliable, .saveSucceeds, .saveFails, .registrySaveSucceeds, .registrySaveFailsRetry, .registryLogSeeded, .registryLogDeleteFails:
            return .identified(UITestScenarios.reliableBass)
        case .identifiedLowConfidence:
            return .identified(UITestScenarios.lowConfidenceBluegill)
        case .noMatch, .detailLoaded, .detailDeleteFails, .logLoading, .logLoaded, .logEmpty,
             .migrationLaunch1, .migrationLaunch2, .spotMapSeeded, .accountSignedOut, .accountSignedIn:
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
    private let inner: (any CatchSaving)?

    init(scenario: UITestScenario, failuresBeforeSuccess: Int = 1, inner: (any CatchSaving)? = nil) {
        self.scenario = scenario
        self.remainingFailures = failuresBeforeSuccess
        self.inner = inner
    }

    func saveDraft(species: Species, photoData: Data) async throws {
        if (scenario == .saveFails || scenario == .registrySaveFailsRetry), remainingFailures > 0 {
            remainingFailures -= 1
            throw UITestCatchSaveError.failed
        }
        if let inner {
            try await inner.saveDraft(species: species, photoData: photoData)
        }
    }
}

private enum UITestCatchSaveError: Error {
    case failed
}

@MainActor
private struct UITestNoLocationProvider: DeviceLocationProviding {
    func requestPermissionIfNeeded() async -> Bool { false }
    func currentLocation() async -> LocationCoordinate2D? { nil }
}

struct UITestSpotRepository: SpotRepository, Sendable {
    static let seededSpots = UITestSpotRepository(
        spots: [
            Spot(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                name: "Embalse de Sau",
                category: .lake,
                summary: "Amplia lámina de agua cerca de Barcelona.",
                longitude: 2.2486,
                latitude: 42.0037,
                distanceMeters: nil
            ),
        ]
    )

    let spots: [Spot]

    func listSpots(region: SpotRegion) async throws -> [Spot] { spots }
    func nearbySpots(from coordinate: LocationCoordinate2D, radiusKilometers: Double) async throws -> [Spot] { spots }
    func spot(id: UUID) async throws -> Spot? { spots.first { $0.id == id } }
    func favoriteSpotIDs() async throws -> Set<UUID> { [] }
    func favoriteSpots() async throws -> [Spot] { [] }
    func setFavorite(spotID: UUID, isFavorite: Bool) async throws {}
}

private actor UITestSignedInAuthProvider: SupabaseAuthProviding {
    static let user = SupabaseUser(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        email: "ui-test@example.com",
        createdAt: Date(timeIntervalSince1970: 1_751_653_800)
    )

    private var activeUser: SupabaseUser?

    init() {
        activeUser = Self.user
    }

    func signUp(email: String, password: String) async throws -> SupabaseSignUpResult {
        let session = Self.session(for: Self.user)
        activeUser = Self.user
        return .signedIn(session)
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let session = Self.session(for: Self.user)
        activeUser = Self.user
        return session
    }

    func signOut() async throws {
        activeUser = nil
    }

    func currentUser() async -> SupabaseUser? {
        activeUser
    }

    func currentSession() async throws -> SupabaseSession? {
        activeUser.map(Self.session(for:))
    }

    nonisolated func stateChanges() -> AsyncStream<SupabaseAuthEvent> {
        AsyncStream { $0.finish() }
    }

    private static func session(for user: SupabaseUser) -> SupabaseSession {
        SupabaseSession(
            accessToken: "ui-test-access-token",
            refreshToken: "ui-test-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800),
            user: user
        )
    }
}

struct UITestNoAuthProvider: SupabaseAuthProviding, Sendable {
    func signUp(email: String, password: String) async throws -> SupabaseSignUpResult {
        throw UITestAuthUnavailable()
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        throw UITestAuthUnavailable()
    }

    func signOut() async throws {}

    func currentUser() async -> SupabaseUser? { nil }

    func currentSession() async throws -> SupabaseSession? { nil }

    func stateChanges() -> AsyncStream<SupabaseAuthEvent> {
        AsyncStream { $0.finish() }
    }
}

private struct UITestAuthUnavailable: Error {}

private struct UITestAccountProfile: ProfileManaging, Sendable {
    let profileValue: AccountProfile?

    init(profileValue: AccountProfile? = nil) {
        self.profileValue = profileValue
    }

    func profile() async throws -> AccountProfile {
        guard let profileValue else { throw UITestAccountUnavailable.unavailable }
        return profileValue
    }

    func updateDisplayName(_ name: String) async throws {}

    func updateAvatar(data: Data, contentType: String) async throws -> String {
        "ui-test-avatar.jpg"
    }

    func avatarData(avatarPath: String) async throws -> Data? { nil }
}

private struct UITestAccountFavorites: FavoritesPresenting, Sendable {
    let favoritesValue: [FavoriteSpot]

    init(favoritesValue: [FavoriteSpot] = []) {
        self.favoritesValue = favoritesValue
    }

    func favorites() async throws -> [FavoriteSpot] { favoritesValue }

    func favoriteSpotIDs() async throws -> Set<UUID> {
        Set(favoritesValue.map(\.spotID))
    }

    func isFavorite(spotID: UUID) async throws -> Bool {
        favoritesValue.contains { $0.spotID == spotID }
    }

    func setFavorite(spotID: UUID, isFavorite: Bool) async throws {}
}

private struct UITestAccountSync: CatchSynchronizing, Sendable {
    let result: CatchSyncResult

    init(result: CatchSyncResult = CatchSyncResult(pushed: 0, pulled: 0, skipped: 0)) {
        self.result = result
    }

    func sync(userID: UUID) async throws -> CatchSyncResult {
        result
    }
}

private enum UITestAccountUnavailable: Error, Sendable {
    case unavailable
}

#endif
