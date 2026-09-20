import XCTest

final class RegistryE2ETests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", scenario]
        app.launch()
        return app
    }

    func testSaveFromScannerAppearsInLogTab() throws {
        let app = launch(scenario: "registrySaveSucceeds")

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")

        app.buttons["scanner.gallerySource"].tap()

        let identifying = app.otherElements["scanner.identifying"]
        XCTAssertTrue(identifying.waitForExistence(timeout: 10), "El estado de carga debe aparecer al identificar la imagen de galería")

        let speciesName = app.staticTexts["scanner.speciesName"]
        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "El resultado debe mostrar el nombre de la especie")
        XCTAssertTrue(speciesName.label.contains("Largemouth Bass"), "El identificador debe devolver Largemouth Bass (registrySaveSucceeds), obtenido: \(speciesName.label)")

        let saveCatch = app.buttons["scanner.saveCatch"]
        XCTAssertTrue(saveCatch.waitForExistence(timeout: 5), "Con la especie identificada debe ofrecerse guardar la captura")
        saveCatch.tap()

        let confirmationAlert = app.alerts["Guardar la captura"]
        XCTAssertTrue(confirmationAlert.waitForExistence(timeout: 5), "Debe aparecer la confirmación de guardado con la especie pre-rellena")
        let saveConfirm = confirmationAlert.buttons["scanner.saveConfirm"].firstMatch
        XCTAssertTrue(saveConfirm.exists, "La confirmación debe permitir guardar la captura")
        saveConfirm.tap()

        let savedSuccessAlert = app.alerts["Captura guardada"]
        XCTAssertTrue(savedSuccessAlert.waitForExistence(timeout: 10), "El guardado con éxito debe confirmar que la captura se ha guardado")
        app.alerts["Captura guardada"].buttons["scanner.saveSuccessContinue"].firstMatch.tap()

        let catchesTab = app.tabBars.buttons["Capturas"]
        XCTAssertTrue(catchesTab.waitForExistence(timeout: 10), "La navegación principal debe ofrecer la pestaña Capturas")
        catchesTab.tap()

        let logSpecies = app.staticTexts["log.speciesName"]
        XCTAssertTrue(logSpecies.waitForExistence(timeout: 10), "El tab Capturas debe mostrar la captura guardada")
        XCTAssertTrue(logSpecies.label.contains("Largemouth Bass"), "La captura guardada desde el escáner debe aparecer en el historial del tab Capturas, obtenido: \(logSpecies.label)")
    }

    func testSaveFailureThenRetryThenAppearsInLogTab() throws {
        let app = launch(scenario: "registrySaveFailsRetry")

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")

        app.buttons["scanner.gallerySource"].tap()

        let identifying = app.otherElements["scanner.identifying"]
        XCTAssertTrue(identifying.waitForExistence(timeout: 10), "El estado de carga debe aparecer al identificar la imagen de galería")

        let speciesName = app.staticTexts["scanner.speciesName"]
        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "El resultado debe mostrar el nombre de la especie")

        let saveCatch = app.buttons["scanner.saveCatch"]
        XCTAssertTrue(saveCatch.waitForExistence(timeout: 5), "Con la especie identificada debe ofrecerse guardar la captura")
        saveCatch.tap()

        let confirmationAlert = app.alerts["Guardar la captura"]
        XCTAssertTrue(confirmationAlert.waitForExistence(timeout: 5), "Debe aparecer la confirmación de guardado")
        confirmationAlert.buttons["scanner.saveConfirm"].firstMatch.tap()

        let failedAlert = app.alerts["No se pudo guardar la captura"]
        XCTAssertTrue(failedAlert.waitForExistence(timeout: 10), "Un fallo de guardado debe informar del fallo y ofrecer reintento")
        let retry = app.buttons["scanner.saveRetry"].firstMatch
        XCTAssertTrue(retry.exists, "El fallo de guardado debe ofrecer reintentar")
        retry.tap()

        let savedSuccessAlert = app.alerts["Captura guardada"]
        XCTAssertTrue(savedSuccessAlert.waitForExistence(timeout: 10), "El reintento tras el fallo debe conseguir guardar la captura")
        app.alerts["Captura guardada"].buttons["scanner.saveSuccessContinue"].firstMatch.tap()

        let catchesTab = app.tabBars.buttons["Capturas"]
        XCTAssertTrue(catchesTab.waitForExistence(timeout: 10), "La navegación principal debe ofrecer la pestaña Capturas")
        catchesTab.tap()

        let logSpecies = app.staticTexts["log.speciesName"]
        XCTAssertTrue(logSpecies.waitForExistence(timeout: 10), "El tab Capturas debe mostrar la captura guardada tras el reintento")
        XCTAssertTrue(logSpecies.label.contains("Largemouth Bass"), "La captura guardada tras el reintento debe aparecer en el historial del tab Capturas, obtenido: \(logSpecies.label)")
    }
}