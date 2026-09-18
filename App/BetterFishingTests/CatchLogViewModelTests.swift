import XCTest

@testable import BetterFishing

@MainActor
final class CatchLogViewModelTests: XCTestCase {
    private let referenceTime: TimeInterval = 800_000_000

    private func makeSpecies(named name: String) -> Species {
        Species(
            id: "species-\(name)",
            commonName: name,
            scientificName: "Scientific \(name)"
        )
    }

    private func makePhotoData() -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x2A, 0x2A])
    }

    private func makeCatch(
        speciesName: String,
        date: Date,
        createdAt: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    ) -> Catch {
        let id = UUID()
        return Catch(
            id: id,
            species: makeSpecies(named: speciesName),
            photoPath: "\(id.uuidString).jpg",
            date: date,
            location: nil,
            notes: "",
            createdAt: createdAt
        )
    }

    private func makeViewModel(repository: any CatchRepository) -> CatchLogViewModel {
        CatchLogViewModel(repository: repository)
    }

    func testLoadOrdersCatchesByDateDescendingTiebreakCreatedAtDescending() async {
        let repository = CatchRepositoryFake()
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSinceReferenceDate: referenceTime)
        let oldest = makeCatch(speciesName: "Oldest", date: base)
        let middle = makeCatch(speciesName: "Middle", date: base.addingTimeInterval(day))
        let newestEarlyCreated = makeCatch(
            speciesName: "Newest Early",
            date: base.addingTimeInterval(2 * day),
            createdAt: base.addingTimeInterval(10)
        )
        let newestLateCreated = makeCatch(
            speciesName: "Newest Late",
            date: base.addingTimeInterval(2 * day),
            createdAt: base.addingTimeInterval(30)
        )
        repository.seed([oldest, newestEarlyCreated, middle, newestLateCreated])
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.catches.count, 4)
        XCTAssertEqual(
            viewModel.catches.map(\.id),
            [newestLateCreated.id, newestEarlyCreated.id, middle.id, oldest.id],
            "El listado ordena por fecha descendente y desempata por createdAt descendente"
        )
    }

    func testLoadOnEmptyRepositoryShowsEmptyStateThenReflectsNewCatch() async throws {
        let repository = CatchRepositoryFake()
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertTrue(viewModel.isEmpty, "Un registro vacío expone el estado vacío")
        XCTAssertTrue(viewModel.catches.isEmpty)

        let saved = try await repository.saveCatch(
            species: makeSpecies(named: "Bass"),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: "primera"
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.catches.count, 1)
        XCTAssertEqual(viewModel.catches.first?.id, saved.id)
    }

    func testLoadRefreshReflectsAddedAndEditedCatchesInLiveOrder() async throws {
        let repository = CatchRepositoryFake()
        let base = Date(timeIntervalSinceReferenceDate: referenceTime)
        let first = try await repository.saveCatch(
            species: makeSpecies(named: "Bass"),
            photoData: makePhotoData(),
            date: base,
            location: nil,
            notes: "primera"
        )
        let viewModel = makeViewModel(repository: repository)
        await viewModel.load()
        XCTAssertEqual(viewModel.catches.count, 1)

        let second = try await repository.saveCatch(
            species: makeSpecies(named: "Trout"),
            photoData: makePhotoData(),
            date: base.addingTimeInterval(86_400),
            location: nil,
            notes: "segunda"
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.catches.count, 2)
        XCTAssertEqual(viewModel.catches.first?.id, second.id, "La captura nueva más reciente encabeza el listado")
        XCTAssertEqual(viewModel.catches.last?.id, first.id)

        try await repository.updateCatch(
            id: second.id,
            date: base.addingTimeInterval(172_800),
            location: nil,
            notes: "editada"
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.catches.count, 2)
        XCTAssertEqual(viewModel.catches.first?.id, second.id, "Editar la fecha reordena el listado en vivo")
        XCTAssertEqual(viewModel.catches.first?.date, base.addingTimeInterval(172_800))
        XCTAssertEqual(viewModel.catches.last?.id, first.id)
    }

    func testListFailureShowsActionableErrorThenRecoveryLoadsList() async throws {
        let repository = CatchRepositoryFake()
        let saved = try await repository.saveCatch(
            species: makeSpecies(named: "Bass"),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )
        repository.listStub = .failure(CatchRepositoryFakeError.listFailed)
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loadFailed)
        XCTAssertEqual(viewModel.errorMessage, CatchLogViewModel.loadFailedMessage)
        XCTAssertTrue(viewModel.catches.isEmpty, "Sin datos previos el fallo deja el listado vacío, no crashea")

        repository.listStub = nil
        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.catches.map(\.id), [saved.id])
    }
}