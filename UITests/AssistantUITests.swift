import XCTest

@MainActor
final class AssistantUITests: XCTestCase {
    func testOrderedProgressWebAndReadableCalculation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-presentation", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose model"].waitForExistence(timeout: 15))
        // A restored chat may initially scroll to the last answer.
        for _ in 0..<4 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Searched the web"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["I’ll check the reference values, then calculate the circumference."].exists)
        XCTAssertTrue(app.staticTexts["No observations were supplied, so I’ll use an illustrative example."].exists)
        XCTAssertFalse(app.buttons["Read response aloud"].isHittable)
        saveScreenshot(app, name: "Response-progress-and-web")
        app.staticTexts["Searched the web"].tap()
        XCTAssertTrue(app.staticTexts["Example reference"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Response-web-sources")
        app.staticTexts["Searched the web"].tap()
        let calculation = app.staticTexts["Calculated with JavaScript"]
        if !calculation.isHittable { app.swipeUp() }
        XCTAssertTrue(calculation.waitForExistence(timeout: 5)); calculation.tap()
        XCTAssertTrue(app.staticTexts["Circumference Km"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["450,270.2391"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "tool_succeeded")).firstMatch.isHittable)
        XCTAssertTrue(app.staticTexts["Technical details"].exists)
        XCTAssertTrue(app.staticTexts["Code"].exists)
        saveScreenshot(app, name: "Response-calculation")
        if calculation.isHittable { calculation.tap() }
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertTrue(app.buttons["Read response aloud"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Read response aloud").count, 1)
        saveScreenshot(app, name: "Response-math-and-answer")
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }
    func testWelcomeCatalogAndSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Continue with ChatGPT"].waitForExistence(timeout: 15))
        saveScreenshot(app, name: "Welcome-light")
        app.buttons["Choose model"].tap()
        XCTAssertTrue(app.navigationBars["Models"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Qwen 3.5 4B"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Model-library")
        app.buttons["Done"].tap()
        app.buttons["Assistant menu"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Settings")
        app.buttons["Close"].tap()
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }

    func testRichConversationArtifactAndHistory() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["study-plan.md"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Copy code"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Conversation-rich-content")
        app.staticTexts["study-plan.md"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Artifact-preview")
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textViews["Edit artifact"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["Personal Assistant"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Recall")
        XCTAssertTrue(app.staticTexts.matching(identifier: "Burgundy study project").firstMatch.waitForExistence(timeout: 5))
        saveScreenshot(app, name: "History-search")
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }
    func testFreshLaunchSidebarFoldersAndAttachmentActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["study-plan.md"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments = ["--ui-library"]
        app.launch()
        XCTAssertTrue(app.staticTexts["What are we working on?"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["study-plan.md"].exists)
        app.buttons["Add to message"].tap()
        XCTAssertTrue(app.buttons["Choose files"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["From Library"].exists)
        XCTAssertFalse(app.buttons["Read responses aloud"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        app.buttons["History"].tap()
        XCTAssertTrue(app.buttons["New folder"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Sidebar-folders")
        app.buttons["New folder"].tap()
        XCTAssertTrue(app.textFields["Folder name"].waitForExistence(timeout: 5))
        app.textFields["Folder name"].tap(); app.textFields["Folder name"].typeText("UI topic \(UUID().uuidString.prefix(6))")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Personal Assistant"].waitForExistence(timeout: 5))
        app.buttons["Options for Burgundy study project"].tap()
        app.buttons["Archive"].tap()
        app.buttons["Archived chats"].tap()
        XCTAssertTrue(app.buttons["Options for Burgundy study project"].waitForExistence(timeout: 5))
        app.buttons["Options for Burgundy study project"].tap()
        app.buttons["Restore"].tap()
        app.buttons["Back to chats"].tap()
        XCTAssertTrue(app.buttons["Options for Burgundy study project"].waitForExistence(timeout: 5))
        app.buttons["Options for Disposable test chat"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete this chat?"].waitForExistence(timeout: 5))
        app.alerts["Delete this chat?"].buttons["Delete chat"].tap()
        XCTAssertFalse(app.buttons["Options for Disposable test chat"].waitForExistence(timeout: 2))
        saveScreenshot(app, name: "Sidebar-managed-chats")
        app.buttons["Close sidebar"].tap()
        app.buttons["Add to message"].tap()
        app.buttons["From Library"].tap()
        XCTAssertTrue(app.staticTexts["sample.csv"].waitForExistence(timeout: 5))
        app.staticTexts["sample.csv"].tap()
        XCTAssertTrue(app.staticTexts["sample.csv"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "File-attachment")
        app.buttons["Assistant menu"].tap()
        app.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Library-files")
        app.staticTexts["study-report.pdf"].tap()
        XCTAssertTrue(app.buttons["Preview original"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "File-detail")
        app.buttons["Preview original"].tap()
        let closePreview = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(closePreview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The verified example sum is 60.5."].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "PDF-preview")
        closePreview.tap()
        XCTAssertTrue(app.buttons["Preview original"].waitForExistence(timeout: 5))
    }
    func testDarkAndLargeTextControlsRemainUsable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty", "--ui-dark", "--ui-large", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose model"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Dictate message"].exists)
        saveScreenshot(app, name: "Welcome-dark-large-text")
        app.buttons["Choose model"].tap()
        XCTAssertTrue(app.navigationBars["Models"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Models-dark-large-text")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Assistant menu"].exists)
    }

    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
