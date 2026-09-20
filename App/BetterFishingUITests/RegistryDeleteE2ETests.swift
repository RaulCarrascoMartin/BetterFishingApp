import XCTest

final class RegistryDeleteE2ETests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", scenario]
        app.launch()
        return app
    }

    private func openCapturesTab(_ app: XCUIApplication) {
        let catchesTab = app.tabBars.buttons["Capturas"]
        XCTAssertTrue(catchesTab.waitForExistence(timeout: 10), "La navegación principal debe ofrecer la pestaña Capturas")
        catchesTab.tap()
    }

    private func openBassDetail(_ app: XCUIApplication) {
        let bassRow = app.staticTexts["Largemouth Bass"]
        XCTAssertTrue(bassRow.waitForExistence(timeout: 10), "El listado sembrado debe mostrar la captura Largemouth Bass")
        bassRow.tap()

        let detailSpecies = app.staticTexts["detail.speciesName"]
        XCTAssertTrue(detailSpecies.waitForExistence(timeout: 10), "Al seleccionar la captura debe navegar al detalle")
        XCTAssertTrue(detailSpecies.label.contains("Largemouth Bass"), "El detalle debe mostrar Largemouth Bass, obtenido: \(detailSpecies.label)")
    }

    @discardableResult
    private func beginDelete(_ app: XCUIApplication) -> XCUIElement {
        let deleteButton = app.buttons["detail.deleteButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10), "Debe existir el botón Eliminar")
        deleteButton.tap()

        let alert = app.alerts["¿Eliminar esta captura?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Borrar debe pedir confirmación")
        return alert
    }

    private func backToList(_ app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Debe existir el botón de retroceso al listado")
        backButton.tap()
    }

    func testDeleteWithConfirmationRemovesFromList() throws {
        let app = launch(scenario: "registryLogSeeded")

        openCapturesTab(app)

        let bassRow = app.staticTexts["Largemouth Bass"]
        XCTAssertTrue(bassRow.waitForExistence(timeout: 10), "El listado sembrado debe mostrar la captura Largemouth Bass")
        XCTAssertTrue(app.staticTexts["Bluegill"].exists, "El listado sembrado debe mostrar también Bluegill")

        openBassDetail(app)

        let cancelAlert = beginDelete(app)
        let cancelDelete = cancelAlert.buttons["detail.cancelDelete"].firstMatch
        XCTAssertTrue(cancelDelete.exists, "La confirmación de borrado debe ofrecer la opción de cancelar")
        cancelDelete.tap()

        let speciesInDetail = app.staticTexts["detail.speciesName"]
        XCTAssertTrue(speciesInDetail.waitForExistence(timeout: 5), "Cancelar la confirmación mantiene la captura en el detalle")
        XCTAssertTrue(speciesInDetail.label.contains("Largemouth Bass"), "Cancelar la confirmación conserva la captura en el detalle, obtenido: \(speciesInDetail.label)")

        backToList(app)
        XCTAssertTrue(bassRow.waitForExistence(timeout: 10), "Cancelar la confirmación no debe eliminar la captura del listado")
        XCTAssertTrue(app.staticTexts["Bluegill"].exists, "Bluegill debe seguir visible tras cancelar el borrado de Bass")

        openBassDetail(app)

        let confirmAlert = beginDelete(app)
        let confirmDelete = confirmAlert.buttons["detail.confirmDelete"].firstMatch
        XCTAssertTrue(confirmDelete.exists, "La confirmación de borrado debe permitir eliminar")
        confirmDelete.tap()

        let removed = app.otherElements["detail.removed"]
        XCTAssertTrue(removed.waitForExistence(timeout: 10), "Confirmar el borrado debe marcar la captura como eliminada")

        backToList(app)

        XCTAssertTrue(
            bassRow.waitForNonExistence(timeout: 10),
            "Tras borrar con confirmación, el listado no debe mostrar Largemouth Bass"
        )
        XCTAssertTrue(app.staticTexts["Bluegill"].exists, "El listado debe seguir mostrando Bluegill tras el borrado de Bass")
    }

    func testDeleteFailurePreservesCatchAndShowsError() throws {
        let app = launch(scenario: "registryLogDeleteFails")

        openCapturesTab(app)

        let bassRow = app.staticTexts["Largemouth Bass"]
        XCTAssertTrue(bassRow.waitForExistence(timeout: 10), "El listado debe mostrar la captura al arrancar el escenario de fallo")

        openBassDetail(app)

        let alert = beginDelete(app)
        let confirmDelete = alert.buttons["detail.confirmDelete"].firstMatch
        XCTAssertTrue(confirmDelete.exists, "La confirmación de borrado debe permitir eliminar")
        confirmDelete.tap()

        let failedAlert = app.alerts["No se pudo eliminar la captura"]
        XCTAssertTrue(failedAlert.waitForExistence(timeout: 10), "Un fallo de borrado debe informar con un mensaje accionable")
        XCTAssertTrue(app.staticTexts["detail.speciesName"].exists, "Un fallo de borrado conserva la captura visible en el detalle")

        let closeError = failedAlert.buttons["detail.errorDismiss"].firstMatch
        XCTAssertTrue(closeError.exists, "El mensaje de fallo debe ofrecer cerrarlo")
        closeError.tap()

        backToList(app)

        XCTAssertTrue(bassRow.waitForExistence(timeout: 10), "Un fallo de borrado debe conservar la captura en el listado")
        XCTAssertTrue(app.staticTexts["Bluegill"].exists, "Bluegill debe seguir visible tras el fallo de borrado de Bass")
    }
}