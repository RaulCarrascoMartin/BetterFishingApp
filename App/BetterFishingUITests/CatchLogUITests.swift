import XCTest

final class CatchLogUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", scenario]
        app.launch()
        return app
    }

    func testLoadedRendersTwoRowsWithSpeciesDateAndPhotos() throws {
        let app = launch(scenario: "logLoaded")

        XCTAssertTrue(app.staticTexts["Largemouth Bass"].waitForExistence(timeout: 10), "El listado debe mostrar la especie Largemouth Bass")
        XCTAssertTrue(app.staticTexts["Bluegill"].waitForExistence(timeout: 5), "El listado debe mostrar la especie Bluegill")

        let speciesLabels = app.staticTexts.matching(NSPredicate(format: "identifier == %@", "log.speciesName"))
        XCTAssertEqual(speciesLabels.count, 2, "Debe haber exactamente 2 filas de especie, obtenido: \(speciesLabels.count)")

        let photos = app.images.matching(NSPredicate(format: "identifier == %@", "log.photo"))
        XCTAssertEqual(photos.count, 2, "Debe haber 2 miniaturas de foto, obtenido: \(photos.count)")

        let dateLabels = app.staticTexts.matching(NSPredicate(format: "identifier == %@", "log.date"))
        XCTAssertEqual(dateLabels.count, 2, "Debe haber 2 etiquetas de fecha, obtenido: \(dateLabels.count)")

        for i in 0..<dateLabels.count {
            XCTAssertFalse(dateLabels.element(boundBy: i).label.isEmpty, "La fecha de la fila \(i) no debe estar vacía")
        }
    }

    func testListOrderShowsNewestCatchFirst() throws {
        let app = launch(scenario: "logLoaded")

        let bass = app.staticTexts["Largemouth Bass"]
        let bluegill = app.staticTexts["Bluegill"]
        XCTAssertTrue(bass.waitForExistence(timeout: 10), "Largemouth Bass (nueva) debe estar visible")
        XCTAssertTrue(bluegill.waitForExistence(timeout: 5), "Bluegill (vieja) debe estar visible")

        XCTAssertTrue(bass.frame.minY < bluegill.frame.minY, "Largemouth Bass (nueva) debe aparecer ANTES de Bluegill (vieja)")
    }

    func testEmptyStateInvitesSavingFirstCatch() throws {
        let app = launch(scenario: "logEmpty")

        XCTAssertTrue(app.otherElements["log.emptyState"].waitForExistence(timeout: 10), "El estado vacío debe invitar a guardar la primera captura")

        let speciesLabels = app.staticTexts.matching(NSPredicate(format: "identifier == %@", "log.speciesName"))
        XCTAssertEqual(speciesLabels.count, 0, "No debe haber filas de capturas")
    }

    func testSelectingCatchNavigatesToDetail() throws {
        let app = launch(scenario: "logLoaded")

        let bass = app.staticTexts["Largemouth Bass"]
        XCTAssertTrue(bass.waitForExistence(timeout: 10), "Largemouth Bass debe estar visible en el listado")
        bass.tap()

        let detailSpecies = app.staticTexts["detail.speciesName"]
        XCTAssertTrue(detailSpecies.waitForExistence(timeout: 10), "Al seleccionar una captura debe navegar al detalle")
        XCTAssertTrue(detailSpecies.label.contains("Largemouth Bass"), "El detalle debe mostrar la especie seleccionada, obtenido: \(detailSpecies.label)")

        XCTAssertTrue(app.images["detail.photo"].waitForExistence(timeout: 5), "El detalle debe mostrar la foto")
    }
}
