import XCTest

@testable import BetterFishing

@MainActor
final class CatchDetailViewModelTests: XCTestCase {
    private let referenceTime: TimeInterval = 800_000_000

    private func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides",
            localizedName: "Lubina americana"
        )
    }

    private func makeLocation() -> LocationCoordinate2D {
        LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
    }

    private func makePhotoData() -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x2A, 0x2A])
    }

    private func makeViewModel(
        repository: CatchRepositoryFake,
        id: UUID,
        photoProvider: @escaping (Catch) -> Data? = { _ in nil }
    ) -> CatchDetailViewModel {
        CatchDetailViewModel(id: id, repository: repository, photoProvider: photoProvider)
    }

    func testLoadResolvesCatchAndPopulatesDetailAndSeedsEditingBindings() async throws {
        let repository = CatchRepositoryFake()
        let date = Date(timeIntervalSinceReferenceDate: referenceTime)
        let location = makeLocation()
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: date,
            location: location,
            notes: "Captura en la orilla"
        )
        let viewModel = makeViewModel(repository: repository, id: saved.id)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.speciesCommonName, "Largemouth Bass")
        XCTAssertEqual(viewModel.speciesScientificName, "Micropterus salmoides")
        XCTAssertEqual(viewModel.location, location)
        XCTAssertEqual(viewModel.notes, "Captura en la orilla")
        XCTAssertNotNil(viewModel.formattedDate)
        XCTAssertEqual(viewModel.editDate, date)
        XCTAssertEqual(viewModel.editLocation, location)
        XCTAssertEqual(viewModel.editNotes, "Captura en la orilla")
    }

    func testLoadForMissingIDShowsNotFound() async {
        let repository = CatchRepositoryFake()
        let viewModel = makeViewModel(repository: repository, id: UUID())

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .notFound)
    }

    func testLoadResolvesThumbnailViaPhotoProvider() async throws {
        let repository = CatchRepositoryFake()
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )
        let providerData = Data([0xAB, 0xCD])
        let viewModel = makeViewModel(
            repository: repository,
            id: saved.id,
            photoProvider: { $0.id == saved.id ? providerData : nil }
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.thumbnailData, providerData)
    }

    func testStartEditingEntersEditingModeSeedingBindings() async throws {
        let repository = CatchRepositoryFake()
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: "original"
        )
        let viewModel = makeViewModel(repository: repository, id: saved.id)
        await viewModel.load()

        viewModel.startEditing()

        XCTAssertEqual(viewModel.state, .editing)
        XCTAssertEqual(viewModel.editDate, saved.date)
        XCTAssertEqual(viewModel.editNotes, "original")
    }

    func testSavePersistsEditedDateLocationAndNotesAndReflectsInDetail() async throws {
        let repository = CatchRepositoryFake()
        let originalDate = Date(timeIntervalSinceReferenceDate: referenceTime)
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: originalDate,
            location: nil,
            notes: "original"
        )
        let viewModel = makeViewModel(repository: repository, id: saved.id)
        await viewModel.load()
        viewModel.startEditing()

        let newDate = Date(timeIntervalSinceReferenceDate: referenceTime + 86_400)
        let newLocation = makeLocation()
        viewModel.editDate = newDate
        viewModel.editNotes = "editada"
        viewModel.editLocation = newLocation

        await viewModel.save()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(repository.receivedUpdateIDs, [saved.id])
        let persisted = try await repository.getCatch(id: saved.id)
        XCTAssertEqual(persisted?.date, newDate)
        XCTAssertEqual(persisted?.location, newLocation)
        XCTAssertEqual(persisted?.notes, "editada")
        XCTAssertEqual(persisted?.species, saved.species)
        XCTAssertEqual(viewModel.location, newLocation)
        XCTAssertEqual(viewModel.notes, "editada")
    }

    func testCancelDiscardsEditsWithoutCallingRepository() async throws {
        let repository = CatchRepositoryFake()
        let originalDate = Date(timeIntervalSinceReferenceDate: referenceTime)
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: originalDate,
            location: makeLocation(),
            notes: "original"
        )
        let viewModel = makeViewModel(repository: repository, id: saved.id)
        await viewModel.load()
        viewModel.startEditing()

        viewModel.editDate = originalDate.addingTimeInterval(86_400)
        viewModel.editNotes = "cambios descartados"
        viewModel.editLocation = nil

        viewModel.cancel()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertTrue(repository.receivedUpdateIDs.isEmpty, "Cancelar la edición no debe llamar a updateCatch")
        let persisted = try await repository.getCatch(id: saved.id)
        XCTAssertEqual(persisted?.date, originalDate)
        XCTAssertEqual(persisted?.notes, "original")
        XCTAssertEqual(persisted?.location, makeLocation())
    }

    func testSaveFailureSurfacesActionableErrorAndPreservesCatchAndRetrySucceeds() async throws {
        let repository = CatchRepositoryFake()
        let originalDate = Date(timeIntervalSinceReferenceDate: referenceTime)
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: originalDate,
            location: nil,
            notes: "original"
        )
        let viewModel = makeViewModel(repository: repository, id: saved.id)
        await viewModel.load()
        viewModel.startEditing()
        viewModel.editDate = originalDate.addingTimeInterval(86_400)
        viewModel.editNotes = "editada"
        repository.updateStub = .failure(CatchRepositoryFakeError.updateFailed)

        await viewModel.save()

        XCTAssertEqual(viewModel.state, .saveFailed)
        XCTAssertEqual(viewModel.errorMessage, CatchDetailViewModel.saveFailedMessage)
        let preserved = try await repository.getCatch(id: saved.id)
        XCTAssertEqual(preserved?.date, originalDate, "Un fallo de guardado conserva la captura sin cambios")
        XCTAssertEqual(preserved?.notes, "original")

        repository.updateStub = nil
        await viewModel.save()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.editNotes, "editada", "El reintento conserva la edición en curso")
        let persisted = try await repository.getCatch(id: saved.id)
        XCTAssertEqual(persisted?.date, originalDate.addingTimeInterval(86_400))
        XCTAssertEqual(persisted?.notes, "editada")
    }

    func testBeginDeleteRequestsConfirmation() async throws {
        let repository = CatchRepositoryFake()
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )
        let viewModel = makeViewModel(repository: repository, id: saved.id)
        await viewModel.load()

        viewModel.beginDelete()

        XCTAssertEqual(viewModel.state, .deletingConfirmation)
        XCTAssertTrue(repository.receivedDeleteIDs.isEmpty, "Solicitar el borrado no elimina todavía")
    }

    func testCancelDeleteReturnsToLoadedWithoutDeleting() async throws {
        let repository = CatchRepositoryFake()
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )
        let viewModel = makeViewModel(repository: repository, id: saved.id)
        await viewModel.load()

        viewModel.beginDelete()
        viewModel.cancelDelete()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertTrue(repository.receivedDeleteIDs.isEmpty, "Cancelar la confirmación no debe llamar a deleteCatch")
    }

    func testConfirmDeleteRemovesCatchAndMarksRemoved() async throws {
        let repository = CatchRepositoryFake()
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )
        let viewModel = makeViewModel(repository: repository, id: saved.id)
        await viewModel.load()
        viewModel.beginDelete()

        await viewModel.confirmDelete()

        XCTAssertEqual(viewModel.state, .removed)
        XCTAssertNil(viewModel.catchEntry)
        XCTAssertEqual(repository.receivedDeleteIDs, [saved.id])
        let persisted = try await repository.getCatch(id: saved.id)
        XCTAssertNil(persisted, "La captura confirmada para borrado desaparece del registro")
    }

    func testDeleteFailurePreservesCatchAndSurfacesActionableErrorAndRetrySucceeds() async throws {
        let repository = CatchRepositoryFake()
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: ""
        )
        let viewModel = makeViewModel(repository: repository, id: saved.id)
        await viewModel.load()
        repository.deleteStub = .failure(CatchRepositoryFakeError.deleteFailed)
        viewModel.beginDelete()

        await viewModel.confirmDelete()

        XCTAssertEqual(viewModel.state, .deleteFailed)
        XCTAssertEqual(viewModel.errorMessage, CatchDetailViewModel.deleteFailedMessage)
        let preserved = try await repository.getCatch(id: saved.id)
        XCTAssertNotNil(preserved, "Un fallo de borrado conserva la captura en el registro")

        repository.deleteStub = nil
        await viewModel.confirmDelete()

        XCTAssertEqual(viewModel.state, .removed, "El reintento tras el fallo puede borrar la captura")
        let persisted = try await repository.getCatch(id: saved.id)
        XCTAssertNil(persisted)
    }

    func testDismissErrorReturnsToLoaded() async throws {
        let repository = CatchRepositoryFake()
        let saved = try await repository.saveCatch(
            species: makeSpecies(),
            photoData: makePhotoData(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: nil,
            notes: "original"
        )
        let viewModel = makeViewModel(repository: repository, id: saved.id)
        await viewModel.load()
        viewModel.startEditing()
        viewModel.editNotes = "editada"
        repository.updateStub = .failure(CatchRepositoryFakeError.updateFailed)

        await viewModel.save()
        XCTAssertEqual(viewModel.state, .saveFailed)

        viewModel.dismissError()

        XCTAssertEqual(viewModel.state, .loaded, "Cerrar el error devuelve al detalle cargado")
    }
}