import XCTest

final class BetterFishingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSmokeLaunchShowsSourceSelectorWithUIUnitDouble() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "identifiedReliable"]
        app.launch()

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")
    }

    func testCameraFlowCapturesAndShowsIdentifiedSpecies() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "identifiedReliable"]
        app.launch()

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")

        app.buttons["scanner.cameraSource"].tap()

        let cameraPreview = app.otherElements["scanner.cameraPreview"]
        XCTAssertTrue(cameraPreview.waitForExistence(timeout: 10), "La preview de cámara debe aparecer con el permiso concedido (stub)")

        app.buttons["scanner.cameraShutter"].tap()

        let identifying = app.otherElements["scanner.identifying"]
        XCTAssertTrue(identifying.waitForExistence(timeout: 10), "El estado de carga debe aparecer al identificar")

        let speciesName = app.staticTexts["scanner.speciesName"]
        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "El resultado debe mostrar el nombre de la especie")
        XCTAssertTrue(speciesName.label.contains("Largemouth Bass"), "La especie debe ser Largemouth Bass (reliableBass), obtenido: \(speciesName.label)")
    }

    func testGallerySelectionShowsLowConfidenceWarning() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "identifiedLowConfidence"]
        app.launch()

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")

        app.buttons["scanner.gallerySource"].tap()

        let identifying = app.otherElements["scanner.identifying"]
        XCTAssertTrue(identifying.waitForExistence(timeout: 10), "El estado de carga debe aparecer al identificar la imagen de galería")

        let speciesName = app.staticTexts["scanner.speciesName"]
        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "El resultado debe mostrar el nombre de la especie")
        XCTAssertTrue(speciesName.label.contains("Bluegill"), "La especie debe ser Bluegill (lowConfidenceBluegill), obtenido: \(speciesName.label)")

        let warning = app.descendants(matching: .any)["scanner.lowConfidenceWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10), "El aviso de fiabilidad debe aparecer con confianza baja")
    }
}
