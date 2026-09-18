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
}