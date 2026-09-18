import XCTest

@testable import BetterFishing

@MainActor
private final class CompositionTestLocationProvider: DeviceLocationProviding {
    private let granted: Bool
    private let coordinate: LocationCoordinate2D

    init(granted: Bool, coordinate: LocationCoordinate2D) {
        self.granted = granted
        self.coordinate = coordinate
    }

    func requestPermissionIfNeeded() async -> Bool {
        granted
    }

    func currentLocation() async -> LocationCoordinate2D? {
        granted ? coordinate : nil
    }
}

@MainActor
final class CompositionIntegrationTests: XCTestCase {
    private func makeSpecies() -> Species {
        Species(
            id: "composition-test-species",
            commonName: "Striped Bass",
            scientificName: "Morone saxatilis"
        )
    }

    private func makePhotoData() -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
    }

    func testScannerCatchSaverAndLogViewModelShareTheSameRepository() async throws {
        let directory = try makeTemporaryDirectory()
        let coordinate = LocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let provider = CompositionTestLocationProvider(granted: true, coordinate: coordinate)
        let repository = LocalFileCatchRepository(directoryURL: directory.url, deviceLocationProvider: provider)
        let species = makeSpecies()
        let photoData = makePhotoData()

        let services = AppComposition.makeRootServices(arguments: [], repository: repository)

        try await services.catchSaver.saveDraft(species: species, photoData: photoData)

        await services.catchLogViewModel.load()

        let matches = services.catchLogViewModel.catches.filter { $0.species == species }
        XCTAssertEqual(matches.count, 1, "La captura guardada por el escáner debe aparecer en el historial del registro")
        XCTAssertEqual(matches.first?.notes, "")
    }

    func testStartupMigrationMakesDraftsAppearAsCatchesAndIsIdempotent() async throws {
        let directory = try makeTemporaryDirectory()
        let catchesDirectoryURL = directory.url.appendingPathComponent("Catches", isDirectory: true)
        let draftsDirectoryURL = directory.url.appendingPathComponent("ProvisionalDrafts", isDirectory: true)
        try FileManager.default.createDirectory(at: draftsDirectoryURL, withIntermediateDirectories: true)

        let species = makeSpecies()
        let photoData = makePhotoData()
        let draft = CatchDraft(
            id: UUID(),
            species: species,
            photoPath: "\(UUID().uuidString).jpg",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .draft
        )
        try photoData.write(to: draftsDirectoryURL.appendingPathComponent(draft.photoPath), options: .atomic)
        try JSONEncoder().encode(draft).write(
            to: draftsDirectoryURL.appendingPathComponent("\(draft.id.uuidString).json"),
            options: .atomic
        )

        let zeroCoordinate = LocationCoordinate2D(latitude: 0, longitude: 0)
        let repository = LocalFileCatchRepository(
            directoryURL: catchesDirectoryURL,
            deviceLocationProvider: CompositionTestLocationProvider(granted: false, coordinate: zeroCoordinate)
        )

        let services = AppComposition.makeRootServices(arguments: [], repository: repository, draftsDirectory: draftsDirectoryURL)

        try await services.migrator.migrateIfNeeded()

        await services.catchLogViewModel.load()
        let firstLoad = services.catchLogViewModel.catches
        XCTAssertEqual(firstLoad.count, 1, "El borrador semillado debe migrarse como una captura del registro")
        XCTAssertEqual(firstLoad.first?.species, species)

        let markerURL = draftsDirectoryURL.appendingPathComponent(".migrated")
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path), "La migración debe escribir el marker .migrated")

        try await services.migrator.migrateIfNeeded()

        await services.catchLogViewModel.load()
        XCTAssertEqual(
            services.catchLogViewModel.catches.count,
            firstLoad.count,
            "Una segunda migración no debe duplicar capturas"
        )
    }

    func testDefaultRootServicesBuildsProductionWiring() {
        let services = AppComposition.makeRootServices(arguments: [])

        XCTAssertNotNil(services.scannerViewModel)
        XCTAssertNotNil(services.catchLogViewModel)
        XCTAssertNotNil(services.catchSaver)
        XCTAssertNotNil(services.migrator)
    }
}