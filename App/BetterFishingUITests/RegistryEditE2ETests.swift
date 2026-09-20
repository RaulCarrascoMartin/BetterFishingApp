import XCTest

final class RegistryEditE2ETests: XCTestCase {
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

    @discardableResult
    private func openBassDetail(_ app: XCUIApplication) -> XCUIElement {
        let bassRow = app.staticTexts["Largemouth Bass"]
        XCTAssertTrue(bassRow.waitForExistence(timeout: 10), "El listado sembrado debe mostrar la captura Largemouth Bass")
        bassRow.tap()

        let detailSpecies = app.staticTexts["detail.speciesName"]
        XCTAssertTrue(detailSpecies.waitForExistence(timeout: 10), "Al seleccionar la captura debe navegar al detalle")
        XCTAssertTrue(detailSpecies.label.contains("Largemouth Bass"), "El detalle debe mostrar Largemouth Bass, obtenido: \(detailSpecies.label)")
        return detailSpecies
    }

    private func backToList(_ app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Debe existir el botón de retroceso al listado")
        backButton.tap()
    }

    private func bassListDate(_ app: XCUIApplication) -> XCUIElement {
        let dates = app.staticTexts.matching(NSPredicate(format: "identifier == %@", "log.date"))
        XCTAssertGreaterThan(dates.count, 0, "El listado debe mostrar fechas")
        return dates.element(boundBy: 0)
    }

    private func openEditMode(_ app: XCUIApplication) {
        let editButton = app.buttons["detail.editButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 10), "Debe existir el botón Editar en modo vista")
        editButton.tap()
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

    private func selectDay28(in app: XCUIApplication, from datePicker: XCUIElement) {
        datePicker.tap()

        // El calendario compacto abre un popover sobre el mes sembrado (julio de 2025).
        let dayButton = app.buttons.matching(NSPredicate(format: "label == %@", "28")).firstMatch
        if dayButton.waitForExistence(timeout: 5) {
            dayButton.tap()
            return
        }

        let dayLabel = app.staticTexts["28"].firstMatch
        XCTAssertTrue(dayLabel.waitForExistence(timeout: 5), "El calendario debe exponer el día 28 para seleccionarlo")
        dayLabel.tap()
    }

    func testEditDateAndNotesFromListReflectsInList() throws {
        let app = launch(scenario: "registryLogSeeded")

        openCapturesTab(app)

        let originalListDate = bassListDate(app).label

        openBassDetail(app)

        let detailDate = app.staticTexts["detail.date"]
        XCTAssertTrue(detailDate.waitForExistence(timeout: 5), "El detalle debe mostrar la fecha")
        let originalDetailDate = detailDate.label

        let notes = app.staticTexts["detail.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5), "El detalle debe mostrar las notas")

        openEditMode(app)

        let notesEditor = app.textViews["detail.editNotes"]
        XCTAssertTrue(notesEditor.waitForExistence(timeout: 5), "El modo edición debe mostrar el editor de notas")
        clearAndType(replacing: notesEditor, with: "Nota E2E 2026")

        let datePicker = app.datePickers["detail.editDate"].firstMatch
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5), "El modo edición debe mostrar el selector de fecha")
        selectDay28(in: app, from: datePicker)

        let saveButton = app.buttons["detail.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Debe existir el botón Guardar")
        saveButton.tap()

        let updatedNotes = app.staticTexts["detail.notes"]
        XCTAssertTrue(updatedNotes.waitForExistence(timeout: 10), "Tras guardar debe volver al modo vista con las notas")
        XCTAssertTrue(updatedNotes.label.contains("Nota E2E 2026"), "El detalle debe reflejar las notas guardadas, obtenido: \(updatedNotes.label)")

        let updatedDetailDate = app.staticTexts["detail.date"]
        XCTAssertTrue(updatedDetailDate.waitForExistence(timeout: 5), "El detalle debe seguir mostrando la fecha")
        XCTAssertTrue(updatedDetailDate.label.contains("28"), "El detalle debe reflejar el día 28 tras guardar, obtenido: \(updatedDetailDate.label)")
        XCTAssertNotEqual(updatedDetailDate.label, originalDetailDate, "La fecha guardada debe diferir de la original")

        backToList(app)

        let updatedListDate = bassListDate(app)
        XCTAssertTrue(updatedListDate.waitForExistence(timeout: 10), "El listado debe seguir mostrando las fechas")
        XCTAssertTrue(updatedListDate.label.contains("28"), "El listado debe reflejar la edición de fecha (día 28), obtenido: \(updatedListDate.label)")
        XCTAssertNotEqual(updatedListDate.label, originalListDate, "La fecha del listado debe diferir de la original tras guardar la edición")

        openBassDetail(app)

        let persistedNotes = app.staticTexts["detail.notes"]
        XCTAssertTrue(persistedNotes.waitForExistence(timeout: 10), "Al reentrar debe mostrarse el detalle")
        XCTAssertTrue(persistedNotes.label.contains("Nota E2E 2026"), "El detalle debe conservar las notas editadas tras reentrar, obtenido: \(persistedNotes.label)")
    }

    func testCancelEditDiscardsChanges() throws {
        let app = launch(scenario: "registryLogSeeded")

        openCapturesTab(app)

        let originalListDate = bassListDate(app).label

        openBassDetail(app)

        let detailDate = app.staticTexts["detail.date"]
        XCTAssertTrue(detailDate.waitForExistence(timeout: 5), "El detalle debe mostrar la fecha")
        let originalDetailDate = detailDate.label

        let notes = app.staticTexts["detail.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5), "El detalle debe mostrar las notas")
        let originalNotes = notes.label

        openEditMode(app)

        let notesEditor = app.textViews["detail.editNotes"]
        XCTAssertTrue(notesEditor.waitForExistence(timeout: 5), "El modo edición debe mostrar el editor de notas")
        clearAndType(replacing: notesEditor, with: "Notas descartadas E2E")

        let datePicker = app.datePickers["detail.editDate"].firstMatch
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5), "El modo edición debe mostrar el selector de fecha")
        selectDay28(in: app, from: datePicker)

        let cancelButton = app.buttons["detail.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Debe existir el botón Cancelar")
        cancelButton.tap()

        let restoredNotes = app.staticTexts["detail.notes"]
        XCTAssertTrue(restoredNotes.waitForExistence(timeout: 10), "Cancelar debe volver al modo vista")
        XCTAssertEqual(restoredNotes.label, originalNotes, "Cancelar debe conservar las notas originales, obtenido: \(restoredNotes.label)")

        let restoredDetailDate = app.staticTexts["detail.date"]
        XCTAssertTrue(restoredDetailDate.waitForExistence(timeout: 5), "El detalle debe seguir mostrando la fecha")
        XCTAssertEqual(restoredDetailDate.label, originalDetailDate, "Cancelar debe conservar la fecha original, obtenido: \(restoredDetailDate.label)")

        backToList(app)

        let restoredListDate = bassListDate(app)
        XCTAssertTrue(restoredListDate.waitForExistence(timeout: 10), "El listado debe seguir mostrando las fechas")
        XCTAssertEqual(restoredListDate.label, originalListDate, "El listado no debe reflejar cambios tras cancelar la edición, obtenido: \(restoredListDate.label)")

        openBassDetail(app)

        let reenteredNotes = app.staticTexts["detail.notes"]
        XCTAssertTrue(reenteredNotes.waitForExistence(timeout: 10), "Al reentrar debe mostrarse el detalle")
        XCTAssertEqual(reenteredNotes.label, originalNotes, "Reentrar debe conservar las notas originales intactas, obtenido: \(reenteredNotes.label)")

        let reenteredDate = app.staticTexts["detail.date"]
        XCTAssertTrue(reenteredDate.waitForExistence(timeout: 5), "El detalle debe seguir mostrando la fecha")
        XCTAssertEqual(reenteredDate.label, originalDetailDate, "Reentrar debe conservar la fecha original intacta, obtenido: \(reenteredDate.label)")
    }
}