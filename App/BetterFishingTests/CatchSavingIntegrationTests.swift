import XCTest

@testable import BetterFishing

@MainActor
private final class DeviceLocationProviderDouble: DeviceLocationProviding {
    private let granted: Bool
    private let coordinate: LocationCoordinate2D?

    private(set) var permissionRequested = false
    private(set) var permissionRequestCount = 0
    private(set) var currentLocationCallCount = 0

    init(granted: Bool, coordinate: LocationCoordinate2D? = nil) {
        self.granted = granted
        self.coordinate = coordinate
    }

    func requestPermissionIfNeeded() async -> Bool {
        permissionRequestCount += 1
        permissionRequested = true
        return granted
    }

    func currentLocation() async -> LocationCoordinate2D? {
        currentLocationCallCount += 1
        return granted ? coordinate : nil
    }
}

@MainActor
final class CatchSavingIntegrationTests: XCTestCase {
    private func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides",
            localizedName: "Lubina americana",
            referenceImageURL: URL(string: "https://fishial.example/species/largemouth.jpg")
        )
    }

    private func makePhotoData() -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x2A, 0x2A])
    }

    func testSaveDraftWithGrantedLocationCreatesCatchWithCorrectData() async throws {
        let directory = try makeTemporaryDirectory()
        let coordinate = LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
        let provider = DeviceLocationProviderDouble(granted: true, coordinate: coordinate)
        let repository = LocalFileCatchRepository(directoryURL: directory.url, deviceLocationProvider: provider)
        let species = makeSpecies()
        let photoData = makePhotoData()

        try await repository.saveDraft(species: species, photoData: photoData)

        let listed = try await repository.listCatches()
        XCTAssertEqual(listed.count, 1)

        let saved = try XCTUnwrap(listed.first)
        XCTAssertEqual(saved.species, species)
        XCTAssertEqual(saved.notes, "")
        XCTAssertEqual(saved.location, coordinate)

        let photoURL = directory.url.appendingPathComponent("\(saved.id.uuidString).jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL.path))
        XCTAssertEqual(try Data(contentsOf: photoURL), photoData)

        let timeDiff = abs(saved.date.timeIntervalSinceNow)
        XCTAssertLessThan(timeDiff, 5)

        XCTAssertTrue(provider.currentLocationCallCount >= 1)
    }

    func testSaveDraftWithDeniedLocationCreatesCatchWithoutLocation() async throws {
        let directory = try makeTemporaryDirectory()
        let provider = DeviceLocationProviderDouble(granted: false)
        let repository = LocalFileCatchRepository(directoryURL: directory.url, deviceLocationProvider: provider)
        let species = makeSpecies()

        try await repository.saveDraft(species: species, photoData: makePhotoData())

        let listed = try await repository.listCatches()
        XCTAssertEqual(listed.count, 1)

        let saved = try XCTUnwrap(listed.first)
        XCTAssertEqual(saved.species, species)
        XCTAssertNil(saved.location)
    }

    func testSaveDraftRequestsPermissionAndRecordsLocationWhenGranted() async throws {
        let directory = try makeTemporaryDirectory()
        let coordinate = LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
        let provider = DeviceLocationProviderDouble(granted: true, coordinate: coordinate)
        let repository = LocalFileCatchRepository(directoryURL: directory.url, deviceLocationProvider: provider)

        try await repository.saveDraft(species: makeSpecies(), photoData: makePhotoData())

        let listed = try await repository.listCatches()
        let saved = try XCTUnwrap(listed.first)
        XCTAssertEqual(saved.location, coordinate)
        XCTAssertEqual(provider.currentLocationCallCount, 1)
    }

    func testSaveDraftThrowsWriteFailedWhenDirectoryIsAFile() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("blocked-path")
        try Data("blocker".utf8).write(to: fileURL)
        let repository = LocalFileCatchRepository(
            directoryURL: fileURL,
            deviceLocationProvider: DeviceLocationProviderDouble(granted: false)
        )

        do {
            try await repository.saveDraft(species: makeSpecies(), photoData: makePhotoData())
            XCTFail("saveDraft debería lanzar CatchSaveError.writeFailed")
        } catch {
            XCTAssertEqual(error as? CatchSaveError, .writeFailed)
        }
    }
}
