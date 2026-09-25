import XCTest

final class SpotMapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", scenario]
        app.launch()
        return app
    }

    func testMapTabRendersAnnotationsAndTappingOneNavigatesToDetail() throws {
        let app = launch(scenario: "spotMapSeeded")

        let mapTab = app.tabBars.buttons["Mapa"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 10), "Debe existir la pestaña Mapa")
        mapTab.tap()

        let annotation = app.buttons["spotMap.annotation"]
        XCTAssertTrue(annotation.waitForExistence(timeout: 10), "El mapa debe renderizar la anotación del spot sembrado")

        annotation.tap()

        let detailName = app.staticTexts["spotDetail.name"]
        XCTAssertTrue(detailName.waitForExistence(timeout: 10), "Tocar la anotación debe navegar al detalle del spot")
        XCTAssertTrue(detailName.label.contains("Embalse de Sau"), "El detalle debe mostrar el spot sembrado, obtenido: \(detailName.label)")
    }
}
