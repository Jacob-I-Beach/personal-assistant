import XCTest

@MainActor
final class AssistantUITests: XCTestCase {
    func testLaunchAndPrimaryScreens() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.staticTexts["A conversation that stays yours"].waitForExistence(timeout: 15))
        saveScreenshot(app, name: "Assistant")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.textFields["MLX vision model repository"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save model settings"].exists)
        saveScreenshot(app, name: "Settings")

        app.tabBars.buttons["Captures"].tap()
        XCTAssertTrue(app.staticTexts["No captures"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Captures")

        app.tabBars.buttons["Assistant"].tap()
        XCTAssertTrue(app.staticTexts["A conversation that stays yours"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }

    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
