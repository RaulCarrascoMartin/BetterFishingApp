import XCTest

final class MigrationE2ETests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func persistenceSuffix() -> String {
        UUID().uuidString
    }

    private func launch(scenario: String, persistenceSuffix: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", scenario, "--ui-persistence", persistenceSuffix]
        app.launch()
        return app
    }

    private func openCapturesTab(_ app: XCUIApplication) {
        let catchesTab = app.tabBars.buttons["Capturas"]
        XCTAssertTrue(catchesTab.waitForExistence(timeout: 20), "La navegación principal debe ofrecer la pestaña Capturas")
        catchesTab.tap()
    }

    private func bassRowCount(in app: XCUIApplication) -> Int {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "Largemouth Bass")).count
    }

    func testSingleLaunchMigratesLegacyDraftIntoLog() throws {
        let app = launch(scenario: "migrationLaunch1", persistenceSuffix: persistenceSuffix())

        openCapturesTab(app)

        let bassRow = app.staticTexts["Largemouth Bass"]
        XCTAssertTrue(
            bassRow.waitForExistence(timeout: 15),
            "El borrador sembrado debe migrarse al historial en el primer arranque"
        )
    }

    func testSecondLaunchDoesNotDuplicate() throws {
        let suffix = persistenceSuffix()
        let app = launch(scenario: "migrationLaunch1", persistenceSuffix: suffix)

        openCapturesTab(app)

        let bassRow = app.staticTexts["Largemouth Bass"]
        XCTAssertTrue(
            bassRow.waitForExistence(timeout: 15),
            "El primer arranque debe migrar el borrador al historial"
        )

        app.terminate()

        app.launchArguments = ["--ui-test-double", "migrationLaunch2", "--ui-persistence", suffix]
        app.launch()

        openCapturesTab(app)

        let secondLaunchBass = app.staticTexts["Largemouth Bass"]
        XCTAssertTrue(
            secondLaunchBass.waitForExistence(timeout: 15),
            "El segundo arranque debe conservar la captura migrada en el historial"
        )

        XCTAssertEqual(
            bassRowCount(in: app),
            1,
            "El segundo arranque no debe duplicar la captura migrada (el marker .migrated debe bloquear la re-migración)"
        )
    }
}