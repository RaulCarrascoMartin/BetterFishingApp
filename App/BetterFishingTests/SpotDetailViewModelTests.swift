import XCTest

@testable import BetterFishing

@MainActor
final class SpotDetailViewModelTests: XCTestCase {
    private func makeSpot() -> Spot {
        Spot(
            id: UUID(),
            name: "Embalse de Sau",
            category: .lake,
            summary: "Amplia lámina de agua cerca de Barcelona.",
            longitude: 2.2486,
            latitude: 42.0037,
            distanceMeters: nil
        )
    }

    private func makeViewModel(
        repository: SpotRepositoryFake,
        auth: SupabaseBaseFake,
        spot: Spot
    ) -> SpotDetailViewModel {
        SpotDetailViewModel(repository: repository, auth: auth, spot: spot)
    }

    func testLoadDerivesFavoriteStateFromFavoriteIDsWhenSessionIsActive() async {
        let spot = makeSpot()
        let repository = SpotRepositoryFake()
        let auth = SupabaseBaseFake()
        auth.isSessionActive = true
        repository.favoriteIDs = [spot.id]
        let viewModel = makeViewModel(repository: repository, auth: auth, spot: spot)

        await viewModel.load()

        XCTAssertTrue(viewModel.isFavorite, "Con sesión y el spot en favoritos, el detalle lo indica")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.sessionRequiredNotice)
        XCTAssertNil(viewModel.toggleErrorMessage)
    }

    func testLoadMarksNotFavoriteWhenSessionIsActiveAndNoFavoriteIDs() async {
        let spot = makeSpot()
        let repository = SpotRepositoryFake()
        let auth = SupabaseBaseFake()
        repository.favoriteIDs = []
        let viewModel = makeViewModel(repository: repository, auth: auth, spot: spot)

        await viewModel.load()

        XCTAssertFalse(viewModel.isFavorite)
    }

    func testLoadWithoutSessionKeepsNotFavoriteEvenWithFavoriteIDs() async {
        let spot = makeSpot()
        let repository = SpotRepositoryFake()
        let auth = SupabaseBaseFake()
        auth.isSessionActive = false
        repository.favoriteIDs = [spot.id]
        let viewModel = makeViewModel(repository: repository, auth: auth, spot: spot)

        await viewModel.load()

        XCTAssertFalse(viewModel.isFavorite, "Sin sesión el favorito no puede estar marcado aunque existan ids")
    }

    func testToggleFavoriteWithSessionCallsSetFavoriteAndUpdatesState() async {
        let spot = makeSpot()
        let repository = SpotRepositoryFake()
        let auth = SupabaseBaseFake()
        repository.favoriteIDs = []
        let viewModel = makeViewModel(repository: repository, auth: auth, spot: spot)
        await viewModel.load()

        await viewModel.toggleFavorite()

        XCTAssertTrue(viewModel.isFavorite)
        XCTAssertEqual(
            repository.recordedFavoriteToggles,
            [SpotRepositoryFake.RecordedFavoriteToggle(spotID: spot.id, isFavorite: true)]
        )
        XCTAssertFalse(viewModel.sessionRequiredNotice)
        XCTAssertNil(viewModel.toggleErrorMessage)
    }

    func testToggleFavoriteWithSessionRemovesFavorite() async {
        let spot = makeSpot()
        let repository = SpotRepositoryFake()
        let auth = SupabaseBaseFake()
        repository.favoriteIDs = [spot.id]
        let viewModel = makeViewModel(repository: repository, auth: auth, spot: spot)
        await viewModel.load()
        XCTAssertTrue(viewModel.isFavorite)

        await viewModel.toggleFavorite()

        XCTAssertFalse(viewModel.isFavorite)
        XCTAssertEqual(
            repository.recordedFavoriteToggles,
            [SpotRepositoryFake.RecordedFavoriteToggle(spotID: spot.id, isFavorite: false)]
        )
    }

    func testToggleFavoriteWithoutSessionShowsNoticeAndDoesNotCallRepository() async {
        let spot = makeSpot()
        let repository = SpotRepositoryFake()
        let auth = SupabaseBaseFake()
        auth.isSessionActive = false
        let viewModel = makeViewModel(repository: repository, auth: auth, spot: spot)
        await viewModel.load()

        await viewModel.toggleFavorite()

        XCTAssertTrue(viewModel.sessionRequiredNotice)
        XCTAssertFalse(viewModel.isFavorite)
        XCTAssertTrue(repository.recordedFavoriteToggles.isEmpty, "Sin sesión el toggle no debe llamar al repositorio")
        XCTAssertTrue(repository.recordedSpotIDs.isEmpty, "Sin sesión el toggle no debe llamar a setFavorite")
    }

    func testSignedOutStateChangeClearsFavoriteWithoutRequerying() async {
        let spot = makeSpot()
        let repository = SpotRepositoryFake()
        let auth = SupabaseBaseFake()
        auth.isSessionActive = true
        repository.favoriteIDs = [spot.id]
        auth.stateChangesEvents = [.signedOut]
        let viewModel = makeViewModel(repository: repository, auth: auth, spot: spot)

        await viewModel.load()
        XCTAssertTrue(viewModel.isFavorite, "Antes del evento, la sesión activa marca el favorito")

        if let task = viewModel.stateChangesTask {
            await task.value
        }

        XCTAssertFalse(viewModel.isFavorite, "El cierre de sesión desmarca el favorito sin reconsultar")
        XCTAssertTrue(viewModel.sessionRequiredNotice)
    }

    func testSignedInStateChangeReloadsFavoriteIDs() async {
        let spot = makeSpot()
        let repository = SpotRepositoryFake()
        let auth = SupabaseBaseFake()
        auth.isSessionActive = false
        repository.favoriteIDs = [spot.id]
        auth.stateChangesEvents = [.signedIn(SupabaseBaseFake.defaultSession)]
        let viewModel = makeViewModel(repository: repository, auth: auth, spot: spot)

        await viewModel.load()
        XCTAssertFalse(viewModel.isFavorite, "Sin sesión al cargar, el spot no se muestra favorito")

        auth.isSessionActive = true
        if let task = viewModel.stateChangesTask {
            await task.value
        }

        XCTAssertTrue(viewModel.isFavorite, "El inicio de sesión recarga los ids de favoritos")
        XCTAssertFalse(viewModel.sessionRequiredNotice)
    }

    func testToggleFavoriteRepositoryErrorSurfacesErrorAndKeepsState() async {
        let spot = makeSpot()
        let repository = SpotRepositoryFake()
        let auth = SupabaseBaseFake()
        repository.favoriteIDs = [spot.id]
        let viewModel = makeViewModel(repository: repository, auth: auth, spot: spot)
        await viewModel.load()
        XCTAssertTrue(viewModel.isFavorite)
        repository.setFavoriteError = .queryFailed("red caída")

        await viewModel.toggleFavorite()

        XCTAssertEqual(viewModel.toggleErrorMessage, SpotDetailViewModel.toggleFailedMessage)
        XCTAssertTrue(viewModel.isFavorite, "Un fallo del toggle conserva el estado de favorito")
        XCTAssertEqual(
            repository.recordedFavoriteToggles,
            [SpotRepositoryFake.RecordedFavoriteToggle(spotID: spot.id, isFavorite: false)]
        )
    }
}