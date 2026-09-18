import XCTest

final class CatchDetailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", scenario]
        app.launch()
        return app
    }

    func testLoadedRendersSpeciesPhotoDateLocationAndNotes() throws {
        let app = launch(scenario: "detailLoaded")

        let speciesName = app.staticTexts["detail.speciesName"]
        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "El detalle debe mostrar el nombre común de la especie")
        XCTAssertTrue(speciesName.label.contains("Largemouth Bass"), "Debe ser Largemouth Bass, obtenido: \(speciesName.label)")

        let scientific = app.staticTexts["detail.speciesScientific"]
        XCTAssertTrue(scientific.exists, "El detalle debe mostrar el nombre científico")
        XCTAssertTrue(scientific.label.contains("Micropterus salmoides"), "Debe ser Micropterus salmoides, obtenido: \(scientific.label)")

        XCTAssertTrue(app.images["detail.photo"].waitForExistence(timeout: 5), "El detalle debe mostrar la foto de la captura")

        let date = app.staticTexts["detail.date"]
        XCTAssertTrue(date.waitForExistence(timeout: 5), "El detalle debe mostrar la fecha/hora")
        XCTAssertFalse(date.label.isEmpty, "La fecha mostrada no debe estar vacía")

        let location = app.staticTexts["detail.location"]
        XCTAssertTrue(location.exists, "El detalle debe mostrar la ubicación")
        XCTAssertTrue(location.label.contains("41.4038"), "La ubicación debe incluir la latitud, obtenido: \(location.label)")
        XCTAssertTrue(location.label.contains("2.1741"), "La ubicación debe incluir la longitud, obtenido: \(location.label)")

        let notes = app.staticTexts["detail.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5), "El detalle debe mostrar las notas")
        XCTAssertTrue(notes.label.contains("Captura de prueba"), "Debe mostrar las notas del fixture, obtenido: \(notes.label)")
    }

    func testEditModeAllowsEditingAndSaveReflectsChanges() throws {
        let app = launch(scenario: "detailLoaded")

        let editButton = app.buttons["detail.editButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 10), "Debe existir el botón Editar en modo vista")
        editButton.tap()

        let notesEditor = app.textViews["detail.editNotes"]
        XCTAssertTrue(notesEditor.waitForExistence(timeout: 5), "El modo edición debe mostrar el editor de notas")
        XCTAssertTrue(
            app.datePickers["detail.editDate"].exists
                || app.buttons["detail.editDate"].exists
                || app.otherElements["detail.editDate"].exists,
            "El modo edición debe mostrar el selector de fecha"
        )
        XCTAssertTrue(app.textFields["detail.latitudeField"].exists, "El modo edición debe mostrar el campo de latitud")
        XCTAssertTrue(app.textFields["detail.longitudeField"].exists, "El modo edición debe mostrar el campo de longitud")

        clearAndType(replacing: notesEditor, with: "Nuevas notas editadas")

        let saveButton = app.buttons["detail.saveButton"]
        XCTAssertTrue(saveButton.exists, "Debe existir el botón Guardar")
        saveButton.tap()

        let notes = app.staticTexts["detail.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10), "Tras guardar debe volver al modo vista con las notas")
        XCTAssertTrue(notes.label.contains("Nuevas notas editadas"), "Las notas guardadas deben reflejar la edición, obtenido: \(notes.label)")
    }

    func testCancelDiscardsEdits() throws {
        let app = launch(scenario: "detailLoaded")

        let editButton = app.buttons["detail.editButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 10), "Debe existir el botón Editar")
        editButton.tap()

        let notesEditor = app.textViews["detail.editNotes"]
        XCTAssertTrue(notesEditor.waitForExistence(timeout: 5), "El modo edición debe mostrar el editor de notas")
        clearAndType(replacing: notesEditor, with: "Cambios descartados")

        let cancelButton = app.buttons["detail.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Debe existir el botón Cancelar")
        cancelButton.tap()

        let notes = app.staticTexts["detail.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10), "Cancelar debe volver al modo vista")
        XCTAssertTrue(notes.label.contains("Captura de prueba"), "Cancelar debe conservar las notas originales, obtenido: \(notes.label)")
    }

    func testDeleteRequiresConfirmationAndCancelsKeepsCatch() throws {
        let app = launch(scenario: "detailLoaded")

        XCTAssertTrue(app.staticTexts["detail.speciesName"].waitForExistence(timeout: 10), "El detalle debe cargar el fixture")

        let deleteButton = app.buttons["detail.deleteButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Debe existir el botón Eliminar")
        deleteButton.tap()

        let alert = app.alerts["¿Eliminar esta captura?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Borrar debe pedir confirmación")
        let confirmDelete = alert.buttons["detail.confirmDelete"].firstMatch
        XCTAssertTrue(confirmDelete.exists, "La confirmación debe permitir eliminar")

        let cancelDelete = alert.buttons["detail.cancelDelete"].firstMatch
        XCTAssertTrue(cancelDelete.exists, "La confirmación debe permitir cancelar")
        cancelDelete.tap()

        XCTAssertTrue(app.staticTexts["detail.speciesName"].waitForExistence(timeout: 5), "Cancelar la confirmación mantiene la captura visible")
        XCTAssertFalse(app.otherElements["detail.removed"].exists, "No debe marcarse la captura como eliminada")
    }

    func testDeleteConfirmsAndRemoves() throws {
        let app = launch(scenario: "detailLoaded")

        XCTAssertTrue(app.staticTexts["detail.speciesName"].waitForExistence(timeout: 10), "El detalle debe cargar el fixture")

        app.buttons["detail.deleteButton"].tap()

        let alert = app.alerts["¿Eliminar esta captura?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Borrar debe pedir confirmación")
        let confirmDelete = alert.buttons["detail.confirmDelete"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5), "La confirmación debe permitir eliminar")
        confirmDelete.tap()

        XCTAssertTrue(app.otherElements["detail.removed"].waitForExistence(timeout: 10), "Confirmar el borrado debe marcar la captura como eliminada")
    }

    func testDeleteFailureShowsActionableErrorAndRetrySucceeds() throws {
        let app = launch(scenario: "detailDeleteFails")

        XCTAssertTrue(app.staticTexts["detail.speciesName"].waitForExistence(timeout: 10), "El fixture de fallo de borrado debe cargar el detalle")

        app.buttons["detail.deleteButton"].tap()

        let alert = app.alerts["¿Eliminar esta captura?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Borrar debe pedir confirmación")
        let confirmDelete = alert.buttons["detail.confirmDelete"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5), "La confirmación debe permitir eliminar")
        confirmDelete.tap()

        let failedAlert = app.alerts["No se pudo eliminar la captura"]
        XCTAssertTrue(failedAlert.waitForExistence(timeout: 10), "Un fallo de borrado debe informar con un mensaje accionable")
        XCTAssertTrue(app.staticTexts["detail.speciesName"].exists, "Un fallo de borrado conserva la captura visible")

        let retry = failedAlert.buttons["detail.errorRetry"].firstMatch
        XCTAssertTrue(retry.exists, "El fallo debe ofrecer reintentar")
        retry.tap()

        XCTAssertTrue(app.otherElements["detail.removed"].waitForExistence(timeout: 10), "Reintentar tras el fallo debe completar el borrado")
    }

    private func clearAndType(replacing element: XCUIElement, with text: String) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        let current = (element.value as? String) ?? ""
        if !current.isEmpty {
            let deletions = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
            element.typeText(deletions)
        }
        element.typeText(text)
    }
}