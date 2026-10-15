import XCTest

@MainActor
final class AssistantUITests: XCTestCase {
    func testLocalMessageStaysLocalWithSavedComputerWork() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-local-isolation", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["On this iPhone"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Choose ChatGPT to open this saved task"].waitForExistence(timeout: 5))
        let composer = app.textFields["message-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap(); composer.typeText("Answer this new local request")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["Answered on this iPhone."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["On this iPhone"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Reconnecting to ChatGPT")).firstMatch.exists)
        saveScreenshot(app, name: "Local-message-with-saved-GPT-task")
        app.buttons["History"].tap()
        let settings = app.buttons["Settings & access"]
        for _ in 0..<8 { if settings.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.tap()
        app.buttons["Privacy & recovery"].tap()
        let paused = app.staticTexts["Notifications and Live Activities are paused in this build. Questions and task status remain available in chat."]
        for _ in 0..<6 { if paused.exists { break }; app.swipeUp() }
        XCTAssertTrue(paused.waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Paused-native-task-notifications")
    }
    func testUnavailableCatalogKeepsSavedModelsAndLocalChoiceUsable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-computer-account", "--ui-catalog-stale", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose model"].waitForExistence(timeout: 15))
        app.buttons["Choose model"].tap()
        XCTAssertTrue(app.buttons["Limited context model"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["model-catalog-status"].exists)
        saveScreenshot(app, name: "Compact-model-chooser")
        app.buttons["model-account-details"].tap()
        XCTAssertTrue(app.staticTexts["connected-chatgpt-account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["model-catalog-status"].label.contains("HTTP 520"))
        XCTAssertTrue(app.buttons["Refresh models"].exists)
        saveScreenshot(app, name: "Connection-diagnostics-separate-from-chooser")
        app.navigationBars["Account & connection"].buttons["Done"].tap()
        app.buttons["Limited context model"].tap()
        XCTAssertTrue(app.staticTexts["Limited context model"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Model availability needs a refresh"].exists)
    }
    func testPublishedComputerImageRendersInlineAndOpensOriginal() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-published-file", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let image = app.buttons["Open image synthetic-screen.png"]
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        for _ in 0..<30 { if image.frame.height > 150 { break }; Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertGreaterThan(image.frame.height, 150)
        let inlineHeight = image.frame.height
        saveScreenshot(app, name: "Published-computer-image-inline")
        image.tap()
        // Quick Look hides its toolbar and renders the image in a remote view.
        // Its inner accessibility tree varies. Verify the full-size controller;
        // retain the original-image screenshot for visual verification as well.
        let original = app.otherElements["QLPreviewControllerView"].firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(original.frame.height, inlineHeight)
        saveScreenshot(app, name: "Published-computer-image-original")
    }
    func testComputerAccountIdentityAppearsAcrossHomeModelsAndSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-computer-account", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose model"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["home-chatgpt-sign-in"].exists)
        app.buttons["Choose model"].tap()
        app.buttons["model-account-details"].tap()
        XCTAssertTrue(app.staticTexts["fixture@example.test"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue with ChatGPT"].exists)
        saveScreenshot(app, name: "Connected-account-models")
        app.navigationBars["Account & connection"].buttons["Done"].tap()
        app.navigationBars["Models"].buttons["Done"].tap()
        app.buttons["History"].tap()
        app.buttons["Settings & access"].tap()
        XCTAssertTrue(app.staticTexts["fixture@example.test"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue with ChatGPT"].exists)
        saveScreenshot(app, name: "Connected-account-settings")
    }
    func testLocalQwenContextAndMemoryControlsAreReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-local-controls", "--ui-qwen-memory", "--ui-qwen-memory-granted", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Response settings"].waitForExistence(timeout: 15))
        app.buttons["Response settings"].tap()
        let context = app.descendants(matching: .any).matching(identifier: "local-working-context").firstMatch
        for _ in 0..<5 { if context.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertEqual(context.value as? String, "65,536 tokens")
        XCTAssertFalse(app.staticTexts["0 tokens"].exists)
        let memory = app.buttons["Memory settings"]
        for _ in 0..<5 { if memory.isHittable && memory.frame.midY < app.frame.height - 150 { break }; app.swipeUp() }
        memory.tap()
        let headroom = app.staticTexts["iOS headroom"]
        for _ in 0..<4 { if headroom.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(headroom.waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Qwen-local-context-and-memory-budget")
        app.navigationBars["Response settings"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Choose model"].exists)
    }
    func testInsufficientQwenAllowanceRequiresAnExplicitSmallerContext() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-local-controls", "--ui-qwen-memory", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Response settings"].waitForExistence(timeout: 15))
        app.buttons["Response settings"].tap()
        let warning = app.staticTexts["More memory headroom needed"]
        for _ in 0..<5 { if warning.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(warning.exists)
        let smaller = app.buttons["32,768 tokens"]
        for _ in 0..<5 { if smaller.isHittable { break }; app.swipeDown() }
        smaller.tap()
        let context = app.descendants(matching: .any).matching(identifier: "local-working-context").firstMatch
        for _ in 0..<5 { if context.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(context.value as? String, "32,768 tokens")
        XCTAssertFalse(warning.exists)
        saveScreenshot(app, name: "Qwen-explicit-smaller-context")
    }
    func testDownloadedModelChooserSeparatesSelectionDetailsAndDownloads() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-local-controls", "--ui-qwen-memory", "--ui-qwen-memory-granted", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose model"].waitForExistence(timeout: 15))
        app.buttons["Choose model"].tap()
        let qwen = app.buttons["Qwen 3.5 4B"]
        XCTAssertTrue(qwen.waitForExistence(timeout: 5))
        XCTAssertEqual(qwen.value as? String, "Selected")
        XCTAssertFalse(app.switches["Allow cellular downloads"].exists)
        saveScreenshot(app, name: "Downloaded-model-compact-chooser")
        app.buttons["Details for Qwen 3.5 4B"].tap()
        let estimate = app.descendants(matching: .any).matching(identifier: "local-context-estimate").firstMatch
        XCTAssertTrue(estimate.waitForExistence(timeout: 5))
        XCTAssertEqual(estimate.value as? String, "65,536 tokens")
        saveScreenshot(app, name: "Qwen-model-details")
        app.navigationBars["Model details"].buttons["Done"].tap()
        let downloads = app.buttons["Browse downloads"]
        for _ in 0..<5 { if downloads.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(downloads.isHittable); downloads.tap()
        XCTAssertTrue(app.buttons["Qwen 3.5 4B details"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Model-downloads-separate-from-chooser")
        app.navigationBars["Downloads"].buttons["Models"].tap()
        app.navigationBars["Models"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Choose model"].exists)
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }
    func testLiveResearchSurvivesReturnAndInteractiveCardsStayUsable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-activity103", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Stop response"].waitForExistence(timeout: 15))
        let research = app.buttons["web-activity-group"].firstMatch
        XCTAssertTrue(research.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        app.activate()
        XCTAssertTrue(app.buttons["Stop response"].waitForExistence(timeout: 8))
        XCTAssertTrue(research.exists)
        let activity = app.buttons["activity-group"].firstMatch
        for _ in 0..<5 { if activity.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(activity.isHittable); activity.tap()
        let category = app.buttons["activity-category-Earlier conversations & files"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.tap()
        saveScreenshot(app, name: "Activity-summary-and-nested-receipts")
        activity.tap()
        for _ in 0..<5 { if research.isHittable { break }; app.swipeUp() }
        research.tap()
        saveScreenshot(app, name: "Live-research-before-completion")
        XCTAssertTrue(app.buttons["Stop response"].exists)
        app.buttons["Assistant menu"].tap(); app.buttons["Finish sample reply"].tap()
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 8))
        let item = app.buttons["Review the trail sources"]
        if app.buttons["Jump to latest message"].exists { app.buttons["Jump to latest message"].tap() }
        for _ in 0..<5 { if item.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(item.isHittable); item.tap()
        let selected = NSPredicate { _, _ in item.value as? String == "Selected" }
        expectation(for: selected, evaluatedWith: app); waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["Ask about these changes"].exists)
        saveScreenshot(app, name: "Interactive-checklist-and-next-action")
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }

    func testActivityComponentsShowWorkingReadyAndReconnectingStates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-activity103", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Assistant menu"].waitForExistence(timeout: 15))
        app.buttons["Assistant menu"].tap(); app.buttons["Activity preview"].tap()
        XCTAssertTrue(app.staticTexts["Comparing the trail sources"].firstMatch.waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Activity-working-compact-expanded-and-lock-screen")
        app.segmentedControls.buttons["Ready"].tap()
        XCTAssertTrue(app.staticTexts["Your reply is ready"].firstMatch.waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Activity-ready-with-green-check")
        app.segmentedControls.buttons["Waiting"].tap()
        XCTAssertTrue(app.staticTexts["Which trail would you prefer?"].firstMatch.waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Activity-needs-your-answer")
        app.segmentedControls.buttons["Reconnecting"].tap()
        XCTAssertTrue(app.staticTexts["Updating your progress"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Your reply is ready"].exists)
        saveScreenshot(app, name: "Activity-reconnecting-without-false-completion")
    }

    func testDailyWorkflowCapturesQuietlyResumesQuestionAndReviewsEvent() {
        executionTimeAllowance = 180
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-daily-work", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Assistant menu"].waitForExistence(timeout: 15))
        app.buttons["Assistant menu"].tap(); app.buttons["Assistant inbox"].tap()
        let note = app.descendants(matching: .any).matching(identifier: "inbox-note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5)); note.tap(); note.typeText("Keep this synthetic note")
        let save = app.buttons["inbox-save"]
        XCTAssertTrue(save.isEnabled)
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["Saved without a model response."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Stop response"].exists)
        saveScreenshot(app, name: "Inbox-save-only")
        app.buttons["Done"].tap()
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["When should we work on it?"].waitForExistence(timeout: 8))
        saveScreenshot(app, name: "Task-question-with-choices")
        app.buttons["Later"].tap()
        let ready = NSPredicate { _, _ in app.buttons["Send message"].exists }
        expectation(for: ready, evaluatedWith: app); waitForExpectations(timeout: 8)
        app.buttons["History"].tap(); app.buttons["New chat"].tap()
        let question = app.staticTexts["When should we work on it?"].firstMatch
        for _ in 0..<7 { if question.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(question.isHittable); saveScreenshot(app, name: "Today-and-needs-you"); question.tap()
        XCTAssertTrue(app.buttons["Afternoon"].waitForExistence(timeout: 5)); app.buttons["Afternoon"].tap()
        XCTAssertNotEqual(app.descendants(matching: .any).matching(identifier: "question-answer").firstMatch.value as? String, "Afternoon")
        XCTAssertTrue(app.buttons["Answer and continue"].isEnabled)
        app.buttons["Answer and continue"].tap()
        let reviewAppeared = app.staticTexts["Save event?"].waitForExistence(timeout: 10)
        if !reviewAppeared { saveScreenshot(app, name: "Daily-workflow-review-missing"); print(app.debugDescription) }
        XCTAssertTrue(reviewAppeared)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Example work session")).firstMatch.exists)
        saveScreenshot(app, name: "Reviewed-calendar-change")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Your example session is saved."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Continue reply"].exists)
        XCTAssertFalse(app.alerts["Could not finish"].exists)
        app.buttons["History"].tap(); app.buttons["New chat"].tap()
        let event = app.staticTexts["Example work session"]
        for _ in 0..<7 { if event.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(event.isHittable); saveScreenshot(app, name: "Today-with-created-event")
    }
    func testGroupedHistoryReadableDetailsRetryAndNoStaleContinueCard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-long-task", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Continue reply"].exists)
        let activity = app.buttons["activity-group"].firstMatch
        for _ in 0..<5 { if activity.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(activity.isHittable); activity.tap()
        let receipt = app.staticTexts["Read saved context"].firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 5)); receipt.tap()
        XCTAssertFalse(app.staticTexts["Technical details"].exists)
        XCTAssertTrue(app.staticTexts["Project decision 1"].firstMatch.exists)
        saveScreenshot(app, name: "Grouped-history-and-readable-details")
        activity.tap()
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["Retrying 1/5"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Visible-connection-retry")
        XCTAssertTrue(app.staticTexts["Recovered reply with saved work intact."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["An unfinished response."].exists)
        XCTAssertFalse(app.buttons["Continue reply"].exists)
        XCTAssertFalse(app.alerts["Could not finish"].exists)
        app.buttons["Assistant menu"].tap(); app.buttons["Task activity"].tap()
        XCTAssertTrue(app.buttons["Share diagnostic report"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Task-activity-and-diagnostic-report")
    }
    func testSavedRouteMemoryUndoAndResumeStayInTheApp() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-continuity", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Continue reply"].waitForExistence(timeout: 15))
        let open = app.buttons["Open in Maps"]
        for _ in 0..<4 { if open.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(open.isHittable)
        saveScreenshot(app, name: "In-chat-route-and-saved-progress")
        for _ in 0..<4 { if app.buttons["Continue reply"].isHittable { break }; app.swipeUp() }
        app.buttons["Continue reply"].tap()
        XCTAssertTrue(app.staticTexts["The saved route is ready. Open it when youÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢re ready."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Continue reply"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Prepare an example walking route").count, 1)
        app.buttons["History"].tap(); app.buttons["Library"].tap()
        app.buttons["Saved memory"].tap()
        app.buttons["History and undo"].tap()
        XCTAssertTrue(app.navigationBars["Memory history"].waitForExistence(timeout: 5))
        app.staticTexts["Example preference"].firstMatch.tap()
        let undo = app.buttons["Undo this change"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        saveScreenshot(app, name: "Memory-history-and-undo")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Use short examples"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }
    func testForegroundReturnContinuesWithoutAnotherUserMessage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-background", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 15)); app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["Progress saved before leaving."].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        XCTAssertTrue(app.staticTexts["Continued from saved progress."].waitForExistence(timeout: 12))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Continue after the app returns").count, 1)
        XCTAssertFalse(app.alerts["Could not finish"].exists)
        saveScreenshot(app, name: "Reply-recovered-on-foreground-return")
    }
    func testKeyboardAndDisclosurePreserveReadingPosition() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-presentation", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Add to message"].waitForExistence(timeout: 15))
        let row = app.staticTexts["Searched the web"]
        for _ in 0..<6 { if row.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(row.isHittable)
        let scroll = app.scrollViews["conversation-scroll"]
        let settled = NSPredicate { _, _ in (scroll.value as? String ?? "").contains("|idle|") }
        expectation(for: settled, evaluatedWith: scroll); waitForExpectations(timeout: 5)
        let before = row.frame.minY
        print("Disclosure before: \(row.frame); \(String(describing: scroll.value)); viewport \(scroll.frame)")
        saveScreenshot(app, name: "Web-disclosure-before")
        row.tap()
        XCTAssertTrue(app.staticTexts["Example reference"].waitForExistence(timeout: 5))
        print("Disclosure open: \(row.frame); \(String(describing: scroll.value))")
        saveScreenshot(app, name: "Web-disclosure-open")
        row.tap()
        print("Disclosure closed: \(row.frame); \(String(describing: scroll.value))")
        saveScreenshot(app, name: "Web-disclosure-closed")
        XCTAssertLessThan(abs(row.frame.minY - before), 24)
        let composer = app.descendants(matching: .any).matching(identifier: "message-composer").firstMatch
        composer.tap(); composer.typeText("A saved draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Dismiss keyboard"].exists)
        app.scrollViews["conversation-scroll"].swipeDown()
        let dismissed = NSPredicate { _, _ in app.keyboards.count == 0 }
        expectation(for: dismissed, evaluatedWith: app); waitForExpectations(timeout: 5)
        saveScreenshot(app, name: "Compact-tools-swipe-keyboard-dismissed")
        app.swipeUp(); app.swipeDown()
        if row.isHittable {
            let settled = row.frame.minY
            for _ in 0..<3 { Thread.sleep(forTimeInterval: 0.2); XCTAssertLessThan(abs(row.frame.minY - settled), 30) }
        }
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }
    func testStreamingFollowsDetachesAndReturnsToFollowing() {
        executionTimeAllowance = 180
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-streaming", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 15)); app.buttons["Send message"].tap()
        XCTAssertTrue(app.buttons["Stop response"].waitForExistence(timeout: 8))
        let scroll = app.scrollViews["conversation-scroll"]
        func position() -> (String, Double, Double, String, Double) {
            let parts = (scroll.value as? String ?? "").split(separator: "|").map(String.init)
            return (parts.first ?? "", parts.count > 1 ? Double(parts[1]) ?? -1 : -1, parts.count > 2 ? Double(parts[2]) ?? -1 : -1, parts.count > 3 ? parts[3] : "", parts.count > 4 ? Double(parts[4]) ?? -1 : -1)
        }
        let moving = NSPredicate { _, _ in let p = position(); return p.0 == "following" && p.1 > 0 }
        expectation(for: moving, evaluatedWith: scroll); waitForExpectations(timeout: 8)
        saveScreenshot(app, name: "Live-tool-and-streaming")
        let initialFollow = position().1
        var prior = initialFollow
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.2)
            let next = position().1; XCTAssertGreaterThanOrEqual(next, prior - 2); prior = next
        }
        XCTAssertGreaterThan(prior, initialFollow + 10, "Following must advance with new text")
        scroll.swipeDown()
        let detached = NSPredicate { _, _ in let p = position(); return p.0 == "reading" && p.3 == "idle" }
        expectation(for: detached, evaluatedWith: scroll); waitForExpectations(timeout: 8)
        Thread.sleep(forTimeInterval: 0.5)
        let readingPosition = position(), reading = readingPosition.1
        Thread.sleep(forTimeInterval: 1)
        let afterReading = position()
        let evidence = XCTAttachment(string: "Before: \(readingPosition); after: \(afterReading)\n" + app.debugDescription)
        evidence.name = "Streaming reading position"; evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertLessThan(abs(afterReading.1 - reading), 8)
        XCTAssertLessThan(abs(afterReading.4 - readingPosition.4), 3, "Visible message anchor moved during reading")
        XCTAssertGreaterThan(afterReading.2, readingPosition.2 + 20, "The response must still grow during the reading check")
        saveScreenshot(app, name: "Streaming-reader-detached")
        // Scroll to the actual bottom rather than using the jump button.
        for _ in 0..<8 { if position().0 == "following" { break }; scroll.swipeUp(velocity: .fast) }
        let returnEvidence = XCTAttachment(string: "After manual swipes: \(position())")
        returnEvidence.name = "Return to bottom position"; returnEvidence.lifetime = .keepAlways; add(returnEvidence)
        let reattached = NSPredicate { _, _ in position().0 == "following" }
        expectation(for: reattached, evaluatedWith: scroll); waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["Stop response"].exists)
        saveScreenshot(app, name: "Streaming-follow-resumed")
        app.buttons["Stop response"].tap()
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue reply"].exists)
    }
    func testHomeActionsOpenRealWorkflowsAndKeepTheUsersWords() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home-greeting"].waitForExistence(timeout: 15))
        for _ in 0..<3 { if app.buttons["Make something"].isHittable { break }; app.swipeUp() }
        app.buttons["Make something"].tap()
        let brief = app.textViews["Creation brief"]
        XCTAssertTrue(brief.waitForExistence(timeout: 5)); brief.tap(); brief.typeText("A two-page study guide")
        app.buttons["Use this brief"].tap()
        let composer = app.descendants(matching: .any).matching(identifier: "message-composer").firstMatch
        XCTAssertEqual(composer.value as? String, "A two-page study guide")
        app.scrollViews["conversation-scroll"].swipeDown()
        for _ in 0..<5 { if app.buttons["Connections"].isHittable { break }; app.swipeUp() }
        app.buttons["Connections"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Location & weather")).firstMatch.tap()
        XCTAssertTrue(app.switches["Use location while IÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢m here"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use my approximate location"].exists)
        saveScreenshot(app, name: "Home-context-controls")
        app.navigationBars["Home context"].buttons["Done"].tap()
        app.navigationBars["Connections"].buttons["Done"].tap()
        for _ in 0..<4 { if app.buttons["Work with files"].isHittable { break }; app.swipeDown() }
        app.buttons["Work with files"].tap()
        let picker = NSPredicate { _, _ in
            app.buttons["Cancel"].exists && (app.navigationBars["Recents"].exists || app.navigationBars["Browse"].exists || app.buttons["Browse"].exists || app.buttons["Recents"].exists || app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].exists)
        }
        saveScreenshot(app, name: "Home-file-picker-opening")
        print("File picker opening hierarchy:\n" + app.debugDescription)
        expectation(for: picker, evaluatedWith: app); waitForExpectations(timeout: 15)
        saveScreenshot(app, name: "Home-file-picker")
    }
    func testAttachmentPreviewWorkingSurfacesAndActualMessageEdit() {
        executionTimeAllowance = 180
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-interactions", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Add to message"].waitForExistence(timeout: 15))
        let picture = app.buttons["Open attached image"].firstMatch
        for _ in 0..<6 { if picture.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(picture.isHittable); picture.tap()
        XCTAssertTrue(app.navigationBars["Image"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic camera + depth"].exists)
        saveScreenshot(app, name: "Image-depth-viewer")
        app.buttons["Done"].tap()
        let option = app.buttons["Option B"]
        for _ in 0..<8 { if option.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(option.isHittable); option.tap()
        let chosen = NSPredicate(format: "value == %@", "Selected")
        expectation(for: chosen, evaluatedWith: option); waitForExpectations(timeout: 5)
        saveScreenshot(app, name: "Interactive-comparison")
        let chart = app.staticTexts["Verified sample values"].firstMatch
        for _ in 0..<5 { if chart.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(chart.isHittable)
        saveScreenshot(app, name: "Native-chart")
        let count = app.sliders["Count"]
        for _ in 0..<6 { if count.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(count.isHittable)
        count.adjust(toNormalizedSliderPosition: 1)
        // The scenario must recompute the displayed result from the changed input.
        // LabeledContent exposes its label and value together in the native accessibility tree.
        let selectedCount = Double(count.value as? String ?? "") ?? 0
        XCTAssertGreaterThan(selectedCount, 4); XCTAssertLessThanOrEqual(selectedCount, 10)
        // A native slider drag can settle one step short of its endpoint.
        // Validate the calculated result for the actual selected value.
        let expectedTotal = (18.5 * selectedCount).formatted(.number.precision(.fractionLength(0...1)))
        XCTAssertTrue(app.staticTexts["Total, " + expectedTotal].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Interactive-scenario-result")
        let first = app.staticTexts["1+1"]
        for _ in 0..<12 { if first.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(first.isHittable)
        app.buttons["Actions for earlier request"].firstMatch.tap()
        app.collectionViews.buttons["Edit message"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Editing message"].waitForExistence(timeout: 5))
        let composer = app.descendants(matching: .any).matching(identifier: "message-composer").firstMatch
        composer.tap(); composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "1+2")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["3"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["1+1"].exists)
        XCTAssertFalse(app.staticTexts["This later message must disappear after editing."].exists)
        saveScreenshot(app, name: "Edited-conversation-replacement")
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }
    func testSourcesThinkingAndPhotoPicker() {
        executionTimeAllowance = 180
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-demo", "--ui-workspace", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let thinking = app.buttons["Response settings"]
        XCTAssertTrue(thinking.waitForExistence(timeout: 15)); thinking.tap()
        for title in ["Low", "Medium", "High", "Extra High", "Max"] {
            if !app.staticTexts[title].exists { app.swipeUp() }
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
        }
        saveScreenshot(app, name: "Thinking-effort")
        app.staticTexts["High"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Response settings"].waitForExistence(timeout: 5))
        for _ in 0..<3 { if app.staticTexts["4 sources"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["4 sources"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["[1] Reference 1"].exists)
        saveScreenshot(app, name: "Sources-collapsed")
        app.staticTexts["4 sources"].tap()
        XCTAssertTrue(app.staticTexts["[1] Reference 1"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Sources-expanded")
        app.buttons["Add to message"].tap()
        app.buttons["Photo library"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Add to message"].isHittable)
        saveScreenshot(app, name: "Photo-library-picker")
        cancel.tap()
        XCTAssertTrue(app.buttons["Add to message"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }
    func testConnectedFolderAndFilesOutputs() {
        executionTimeAllowance = 180
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-demo", "--ui-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let addToMessage = app.buttons["Add to message"]
        XCTAssertTrue(addToMessage.waitForExistence(timeout: 15))
        // Fixture content becomes visible before folder setup finishes. The
        // loading overlay intentionally disables controls until it is ready.
        expectation(for: NSPredicate(format: "enabled == true AND hittable == true"), evaluatedWith: addToMessage)
        waitForExpectations(timeout: 20)
        addToMessage.tap()
        let connectedFolders = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Connected folders")).firstMatch
        XCTAssertTrue(connectedFolders.waitForExistence(timeout: 5))
        connectedFolders.tap()
        XCTAssertTrue(app.staticTexts["Sample workspace"].waitForExistence(timeout: 5))
        app.staticTexts["Sample workspace"].tap()
        XCTAssertTrue(app.switches["Use in this chat"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Folder-access")
        app.buttons["Browse files"].tap()
        XCTAssertTrue(app.staticTexts["notes.md"].waitForExistence(timeout: 5))
        app.staticTexts["notes.md"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Verified total: 60.5")).firstMatch.waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Connected-file")
        for _ in 0..<3 { app.navigationBars.buttons.element(boundBy: 0).tap() }
        app.buttons["Done"].tap()
        app.buttons["History"].tap(); app.buttons["Library"].tap()
        app.buttons["Outputs in Files"].tap()
        XCTAssertTrue(app.staticTexts["verified-total.csv"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Files-outputs")
        app.staticTexts["verified-total.csv"].tap()
        XCTAssertTrue(app.buttons["Export another copy"].waitForExistence(timeout: 5))
        app.buttons["Export another copy"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 8))
        saveScreenshot(app, name: "Native-file-export")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Export completed. Cloud sync depends on the selected provider."].waitForExistence(timeout: 8))
        saveScreenshot(app, name: "Native-export-completed")
        app.buttons["Export another copy"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 8))
        // Drag the blank sheet margin above the navigation controls. The title itself opens a path menu.
        let header = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: app.buttons["Save"].frame.minY - 16))
        header.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)))
        if !app.staticTexts["Export cancelled."].waitForExistence(timeout: 2) {
            // Some provider locations expose Cancel only after returning to their root.
            for _ in 0..<3 {
                if app.buttons["Cancel"].firstMatch.isHittable { app.buttons["Cancel"].firstMatch.tap(); break }
                let back = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons["BackButton"]
                if back.isHittable { back.tap() } else { break }
            }
        }
        XCTAssertTrue(app.staticTexts["Export cancelled."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }
    func testOrderedProgressWebAndReadableCalculation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-presentation", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose model"].waitForExistence(timeout: 15))
        // A restored chat may initially scroll to the last answer.
        for _ in 0..<4 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Searched the web"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["IÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ll check the reference values, then calculate the circumference."].exists)
        XCTAssertTrue(app.staticTexts["No observations were supplied, so IÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ll use an illustrative example."].exists)
        XCTAssertFalse(app.buttons["Read response aloud"].isHittable)
        saveScreenshot(app, name: "Response-progress-and-web")
        app.staticTexts["Searched the web"].tap()
        XCTAssertTrue(app.staticTexts["Example reference"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Response-web-sources")
        app.staticTexts["Searched the web"].tap()
        let activity = app.buttons["activity-group"].firstMatch
        for _ in 0..<4 { if activity.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(activity.isHittable); activity.tap()
        let calculation = app.staticTexts["Calculated with JavaScript"]
        if !calculation.isHittable { app.swipeUp() }
        XCTAssertTrue(calculation.waitForExistence(timeout: 5)); calculation.tap()
        XCTAssertTrue(app.staticTexts["Circumference Km"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["450,270.2391"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "tool_succeeded")).firstMatch.isHittable)
        XCTAssertFalse(app.staticTexts["Technical details"].exists)
        XCTAssertTrue(app.buttons["Copy diagnostic record"].exists)
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
        app.buttons["Browse downloads"].tap()
        XCTAssertTrue(app.buttons["Qwen 3.5 4B details"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Model-library")
        app.navigationBars["Downloads"].buttons["Models"].tap()
        app.buttons["Done"].tap()
        app.buttons["History"].tap()
        app.buttons["Settings & access"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Settings")
        app.buttons["Done"].tap()
        XCTAssertFalse(app.alerts["Could not finish"].exists)
    }

    func testRichConversationArtifactAndHistory() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Files in this chat"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Copy code"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Conversation-rich-content")
        app.buttons["Files in this chat"].tap()
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
        executionTimeAllowance = 180
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Files in this chat"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments = ["--ui-library"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home-greeting"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["user-message-text"].exists)
        XCTAssertFalse(app.buttons["Read response aloud"].exists)
        XCTAssertTrue(app.staticTexts["Recently created"].exists)
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
        app.buttons["Select sample.csv"].tap()
        app.buttons["Add 1"].tap()
        print("After Library attachment, app state: \(app.state.rawValue)\n" + app.debugDescription)
        saveScreenshot(app, name: "After-library-attachment")
        XCTAssertTrue(app.staticTexts["sample.csv"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "File-attachment")
        app.buttons["History"].tap()
        app.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Library-files")
        app.staticTexts["study-report.pdf"].tap()
        XCTAssertTrue(app.buttons["File info"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "File-detail")
        XCTAssertTrue(app.staticTexts["The verified example sum is 60.5."].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "PDF-preview")
        app.buttons["File info"].tap()
        XCTAssertTrue(app.navigationBars["File info"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }
    func testDarkAndLargeTextControlsRemainUsable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty", "--ui-dark", "--ui-large", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose model"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Dictate message"].exists)
        let heading = app.staticTexts["home-greeting"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(heading.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        saveScreenshot(app, name: "Welcome-dark-large-text")
        app.buttons["Choose model"].tap()
        XCTAssertTrue(app.navigationBars["Models"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Models-dark-large-text")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Assistant menu"].exists)
    }

    func testFullWidthComposerContextAndImmediateConnectedSend() {
        executionTimeAllowance = 180
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose model"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["New chat"].exists)
        let composer = app.descendants(matching: .any).matching(identifier: "message-composer").firstMatch
        expectation(for: NSPredicate(format: "enabled == true AND hittable == true"), evaluatedWith: composer)
        waitForExpectations(timeout: 15)
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        composer.typeText("A synthetic message long enough to wrap naturally across the full width of the input.")
        XCTAssertGreaterThan(composer.frame.width, app.frame.width * 0.78)
        saveScreenshot(app, name: "Full-width-composer")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["Your synthetic request started without another connection prompt."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Allow for this conversation"].exists)
        let copy = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "final-response-actions", "Copy message")).allElementsBoundByIndex.last!
        copy.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2))
        saveScreenshot(app, name: "Copied-confirmation")
        app.buttons["Response settings"].tap()
        for _ in 0..<5 { if app.buttons["1,000,000 tokens"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["1,000,000 tokens"].isHittable)
        app.buttons["1,000,000 tokens"].tap()
        saveScreenshot(app, name: "Brain-context-million")
        app.buttons["Done"].tap()
        app.buttons["Choose model"].tap()
        XCTAssertFalse(app.buttons["Working context"].exists)
        app.buttons["Limited context model"].tap()
        app.buttons["Response settings"].tap()
        for _ in 0..<4 { if app.buttons["252,000 tokens"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["252,000 tokens"].exists)
        XCTAssertFalse(app.buttons["1,000,000 tokens"].exists)
        saveScreenshot(app, name: "Brain-context-smaller-model")
        app.buttons["252,000 tokens"].tap(); app.buttons["Done"].tap()
        XCTAssertFalse(app.alerts["Could not finish"].exists)
        app.buttons["Assistant menu"].tap()
        XCTAssertFalse(app.buttons["New conversation"].exists); XCTAssertFalse(app.buttons["Settings"].exists); XCTAssertFalse(app.buttons["From Library"].exists)
        saveScreenshot(app, name: "Focused-chat-menu")
    }

    func testToolExpansionAndLatestButtonPreserveIntentionalPosition() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-long-task", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 15))
        let group = app.buttons["activity-group"].firstMatch
        for _ in 0..<5 { if group.isHittable { break }; app.swipeDown() }
        let before = group.frame.minY; group.tap()
        XCTAssertLessThan(abs(group.frame.minY - before), 5)
        let row = app.staticTexts["Read saved context"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let rowBefore = row.frame.minY; row.tap()
        XCTAssertLessThan(abs(row.frame.minY - rowBefore), 5)
        saveScreenshot(app, name: "Nested-tool-hierarchy")
        let jump = app.buttons["Jump to latest message"]
        for _ in 0..<4 { if jump.exists { break }; app.swipeDown() }
        XCTAssertTrue(jump.isHittable); jump.tap()
        let atBottom = NSPredicate { _, _ in !app.buttons["Jump to latest message"].exists }
        expectation(for: atBottom, evaluatedWith: app); waitForExpectations(timeout: 5)
        let scroll = app.scrollViews["conversation-scroll"]
        print("After jump: \(String(describing: scroll.value)); scroll frame: \(scroll.frame); last text: \(app.staticTexts["The current request is complete."].frame)")
        saveScreenshot(app, name: "Jump-to-latest-visible")
        // Markdown text is a readable accessibility element, not a tap target.
        // The button tap must reach the bottom and reveal the complete answer.
        let answer = app.staticTexts["The current request is complete."]
        XCTAssertTrue(answer.exists)
        XCTAssertGreaterThan(answer.frame.height, 0)
        XCTAssertGreaterThanOrEqual(answer.frame.minY, scroll.frame.minY)
        XCTAssertLessThanOrEqual(answer.frame.maxY, scroll.frame.maxY)
    }

    func testCompactQuestionKeepsCustomAnswerEmptyAndShowsInlineHistory() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-daily-work", "--ui-question-only", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "enabled == true AND hittable == true"), evaluatedWith: send)
        waitForExpectations(timeout: 15); send.tap()
        XCTAssertTrue(app.buttons["Morning"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.navigationBars["Needs you"].frame.minY, app.frame.height * 0.3)
        app.buttons["Morning"].tap()
        let custom = app.descendants(matching: .any).matching(identifier: "question-answer").firstMatch
        XCTAssertNotEqual(custom.value as? String, "Morning")
        XCTAssertTrue(app.buttons["Answer and continue"].isEnabled)
        saveScreenshot(app, name: "Compact-question-selected-choice")
        app.buttons["Answer and continue"].tap()
        XCTAssertTrue(app.staticTexts["Your answer is saved in the conversation."].waitForExistence(timeout: 10))
        let question = app.staticTexts["When should we work on it?"].firstMatch
        let answer = app.staticTexts["Morning"].firstMatch
        XCTAssertTrue(question.exists); XCTAssertTrue(answer.exists)
        XCTAssertLessThan(question.frame.minY, answer.frame.minY)
        saveScreenshot(app, name: "Question-and-answer-inline")
    }
    func testColdReturnKeepsManualContinueAfterEarlierRecoveryLimit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-recovery09", "--ui-recovery09-seed", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 15))
        let ready = NSPredicate { _, _ in app.buttons["History"].isEnabled }
        expectation(for: ready, evaluatedWith: app); waitForExpectations(timeout: 15)
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-recovery09-seed" }; app.launch()
        XCTAssertTrue(app.staticTexts["The earlier work stays saved."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["home-greeting"].exists)
        let resume = app.buttons["Continue reply"]
        XCTAssertTrue(resume.isHittable)
        saveScreenshot(app, name: "Returned-task-with-continue")
        resume.tap()
        XCTAssertTrue(app.staticTexts["Your saved work continued."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Continue reply"].exists)
        saveScreenshot(app, name: "Manual-fourth-continuation-complete")
    }
    func testHealthCatalogShowsBroaderTypesWithoutRequestingPersonalData() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let menu = app.buttons["Assistant menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "enabled == true AND hittable == true"), evaluatedWith: menu)
        waitForExpectations(timeout: 15); menu.tap(); app.collectionViews.buttons["Connections"].firstMatch.tap()
        let health = app.staticTexts["Health"].firstMatch
        XCTAssertTrue(health.waitForExistence(timeout: 5)); health.tap()
        let data = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Connected data")).firstMatch
        XCTAssertTrue(data.waitForExistence(timeout: 5)); data.tap()
        XCTAssertTrue(app.buttons["Select all available"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Health-data-connections")
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("blood pressure")
        let systolic = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", "systolic")).firstMatch
        XCTAssertTrue(systolic.waitForExistence(timeout: 5))
        XCTAssertTrue(systolic.isHittable, "Search results must be reachable above the keyboard without scrolling past the introduction.")
        saveScreenshot(app, name: "Health-type-search")
    }

    func testShortUserContentRemainsAtTheRightEdge() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-interactions", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Add to message"].waitForExistence(timeout: 15))
        let picture = app.buttons["Open attached image"].firstMatch
        for _ in 0..<6 { if picture.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(picture.isHittable)
        XCTAssertLessThan(app.frame.maxX - picture.frame.maxX, 40)
        saveScreenshot(app, name: "Right-aligned-user-image")
        let text = app.staticTexts["1+1"]
        for _ in 0..<8 { if text.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(text.isHittable)
        XCTAssertLessThan(app.frame.maxX - text.frame.maxX, 65)
        saveScreenshot(app, name: "Right-aligned-short-message")
    }

    func testHomeUsesAContextualGreeting() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let greeting = app.staticTexts["home-greeting"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 15))
        XCTAssertFalse(greeting.label.hasPrefix("Good "))
        XCTAssertFalse(greeting.label.isEmpty)
        saveScreenshot(app, name: "Contextual-home-greeting")
    }

    func testComputerAndContactsHaveNativeConnectionControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Assistant menu"].waitForExistence(timeout: 15))
        app.buttons["Assistant menu"].tap(); app.collectionViews.buttons["Connections"].firstMatch.tap()
        let computer = app.buttons.containing(.staticText, identifier: "Computer").firstMatch
        XCTAssertTrue(computer.waitForExistence(timeout: 5)); computer.tap()
        XCTAssertTrue(app.buttons["Scan computer code"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Computer-connection")
        app.navigationBars["Computer"].buttons["Done"].tap()
        let contacts = app.buttons.containing(.staticText, identifier: "Contacts").firstMatch
        XCTAssertTrue(contacts.waitForExistence(timeout: 5)); contacts.tap()
        XCTAssertTrue(app.buttons["Connect Contacts"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Contacts-connection")
    }


    private func productApp(_ mode: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-product117", "--ui-product117-" + mode, "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Add to message"].waitForExistence(timeout: 15))
        return app
    }
    private func openProductLibrary(_ app: XCUIApplication) {
        app.buttons["History"].tap(); app.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }
    func testProduct117DraftRestoresWithoutChangingSavedRevision() {
        let app = productApp("editor"); openProductLibrary(app)
        app.collectionViews.staticTexts["journey-notes.md"].firstMatch.tap(); app.buttons["Edit"].tap()
        let editor = app.textViews["Edit artifact"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("\nDraft amendment")
        XCTAssertTrue(app.staticTexts["Draft saved on this device"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 15)); openProductLibrary(app)
        app.collectionViews.staticTexts["journey-notes.md"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue((editor.value as? String ?? "").contains("Draft amendment"))
        saveScreenshot(app, name: "Product117-restored-draft")
        app.buttons["Draft actions"].tap(); app.buttons["View saved revision"].tap()
        XCTAssertTrue(app.staticTexts["Saved revision 1"].waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["Draft amendment"].exists)
        app.buttons["Resume draft"].tap(); app.buttons["Draft actions"].tap(); app.buttons["Discard draft"].tap()
        app.buttons["Discard draft"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Saved revision 1"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["Resume draft"].exists)
        app.buttons["Edit"].tap(); editor.tap(); editor.typeText("\nA committed revision")
        app.buttons["Save revision"].tap()
        XCTAssertTrue(app.staticTexts["Saved revision 2"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Product117-saved-revision")
    }
    func testProduct117AttachmentsPreviewCancelAndAddPreserveDraft() {
        let app = productApp("attachments")
        let composer = app.descendants(matching: .any).matching(identifier: "message-composer").firstMatch
        composer.tap(); composer.typeText("Keep my draft")
        app.buttons["Add to message"].tap(); app.buttons["From Library"].tap()
        XCTAssertTrue(app.buttons["Select journey-table.csv"].waitForExistence(timeout: 5))
        app.buttons["Preview journey-table.csv"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "=1+1")).firstMatch.waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Product117-file-preview")
        app.buttons["Done"].tap(); app.buttons["Preview journey-preview.pdf"].tap()
        XCTAssertTrue(app.buttons["File info"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Synthetic preview of the original PDF.")).firstMatch.waitForExistence(timeout: 20), "Verify the document content, not just the preview toolbar.")
        XCTAssertFalse(app.staticTexts["Preview unavailable"].exists)
        saveScreenshot(app, name: "Product117-original-PDF-preview")
        app.buttons["Done"].tap(); app.buttons["Select journey-table.csv"].tap(); app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Remove journey-table.csv from this message"].exists)
        XCTAssertEqual(composer.value as? String, "Keep my draft")
        app.buttons["Add to message"].tap(); app.buttons["From Library"].tap()
        app.buttons["Select journey-table.csv"].tap(); app.buttons["Add 1"].tap()
        XCTAssertTrue(app.buttons["Remove journey-table.csv from this message"].waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Keep my draft")
        saveScreenshot(app, name: "Product117-attached-draft")
    }
    func testProduct117SearchReturnsToExactOldMessageAndKeepsQuery() {
        let app = productApp("search")
        app.buttons["History"].tap()
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("amber telescope")
        let hit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-match-")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5)); hit.tap()
        XCTAssertTrue(app.buttons["Back to results"].waitForExistence(timeout: 5))
        let target = app.staticTexts["Exact old result: amber telescope"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(target.frame.maxY, 120); XCTAssertLessThan(target.frame.minY, app.frame.height - 130)
        saveScreenshot(app, name: "Product117-exact-history-landing")
        app.buttons["Back to results"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5)); XCTAssertEqual(search.value as? String, "amber telescope")
        XCTAssertTrue(hit.exists)
    }
    func testProduct117ScenarioExactEntryUndoAndAskRemainDraftOnly() {
        let app = productApp("surfaces")
        let exact = app.buttons["Set exact Minutes"]
        for _ in 0..<6 { if exact.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(exact.isHittable); exact.tap()
        let field = app.textFields["scenario-exact-value"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "30")
        app.buttons["Apply value"].tap()
        XCTAssertTrue(app.staticTexts["Points, 60"].waitForExistence(timeout: 5))
        let undo = app.buttons["Undo change"]
        for _ in 0..<4 { if undo.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(undo.isHittable); undo.tap()
        XCTAssertTrue(app.staticTexts["Points, 40"].waitForExistence(timeout: 5))

        let ask = app.buttons["Ask about these changes"]
        for _ in 0..<5 { if ask.isHittable { break }; app.swipeUp() }
        ask.tap()
        let composer = app.descendants(matching: .any).matching(identifier: "message-composer").firstMatch
        XCTAssertTrue((composer.value as? String ?? "").contains("Explain these changes"))
        XCTAssertFalse(app.buttons["Stop response"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic response received the selected context."].exists)
        saveScreenshot(app, name: "Product117-contextual-draft")
    }
    func testProduct117PreferenceSavesWithoutGlobalSaveModal() {
        let app = productApp("settings")
        app.buttons["History"].tap(); app.buttons["Settings & access"].tap(); app.buttons["Models"].tap()
        let toggle = app.switches["Allow cellular downloads"]
        for _ in 0..<5 { if toggle.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        let old = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value != %@", old ?? "0"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        let changed = toggle.value as? String
        XCTAssertNotEqual(changed, old)
        app.buttons["Done"].tap(); XCTAssertFalse(app.alerts["Settings saved"].exists)
        app.buttons["History"].tap(); app.buttons["Settings & access"].tap(); app.buttons["Models"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); XCTAssertEqual(toggle.value as? String, changed)
        saveScreenshot(app, name: "Product117-immediate-preferences")
    }
    func testProduct117DictationDoesNotCancelAnActiveResponse() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-streaming", "--ui-dark"]
        app.launch(); XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 15)); app.buttons["Send message"].tap()
        XCTAssertTrue(app.buttons["Stop response"].waitForExistence(timeout: 10))
        // Wait for accepted input and actual stream content before entering the
        // next draft; Stop appears as soon as the request starts preparing.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Line 1. More of the example.")).firstMatch.waitForExistence(timeout: 12))
        let composer = app.descendants(matching: .any).matching(identifier: "message-composer").firstMatch
        composer.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        composer.typeText("My next draft")
        let beforeDictation = composer.value as? String
        print("Synthetic draft before microphone tap: " + (beforeDictation ?? "<missing>"))
        XCTAssertEqual(beforeDictation, "My next draft", "Establish the typed draft before testing the microphone action.")
        app.buttons["Dictate message"].tap()
        XCTAssertTrue(app.staticTexts["Finish or stop the response before dictating. Your draft and current work are kept."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stop response"].exists)
        XCTAssertEqual(composer.value as? String, beforeDictation)
        saveScreenshot(app, name: "Product117-dictation-does-not-stop-work")
        app.buttons["Stop response"].tap()
    }

    func testAudit120BrowseSavedChatKeepsResponseAndDraftOwnedByOriginal() {
        let app = productApp("browse")
        let composer = app.descendants(matching: .any).matching(identifier: "message-composer").firstMatch
        composer.tap(); composer.typeText("Synthetic active request"); app.buttons["Send message"].tap()
        XCTAssertTrue(app.buttons["Stop response"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Line 1. More of the example.")).firstMatch.waitForExistence(timeout: 12))
        composer.tap(); composer.typeText("Keep my next draft")
        app.buttons["History"].tap(); app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Saved reference chat")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Reference answer stays in its own chat."].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Return"].exists)
        XCTAssertFalse(app.buttons["Edit message"].isEnabled)
        saveScreenshot(app, name: "Audit120-browse-while-working")
        app.buttons["Return"].tap()
        XCTAssertTrue(app.buttons["Stop response"].waitForExistence(timeout: 5)); XCTAssertEqual(composer.value as? String, "Keep my next draft")
        app.buttons["Stop response"].tap()
    }
    func testAudit120CreateProjectAndContinueWithoutSending() {
        let app = productApp("projects")
        app.buttons["History"].tap(); app.buttons["sidebar-projects"].tap()
        XCTAssertTrue(app.buttons["Create project"].waitForExistence(timeout: 5)); app.buttons["Create project"].tap()
        let title = app.textFields["project-title"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("My synthetic project")
        app.buttons["Create"].tap()
        let project = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "My synthetic project")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 8)); project.tap()
        XCTAssertTrue(app.buttons["Continue project"].waitForExistence(timeout: 5)); saveScreenshot(app, name: "Audit120-project-detail")
        app.buttons["Continue project"].tap()
        let composer = app.descendants(matching: .any).matching(identifier: "message-composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "Continue this project"), evaluatedWith: composer); waitForExpectations(timeout: 8)
        XCTAssertFalse(app.buttons["Stop response"].exists)
    }
    func testAudit120ConversationRestoreKeepsPriorVersionAndDoesNotExecute() {
        let app = productApp("branches")
        XCTAssertTrue(app.staticTexts["Revised branch answer"].waitForExistence(timeout: 5))
        app.buttons["Assistant menu"].tap(); app.buttons["Conversation history"].tap()
        XCTAssertTrue(app.buttons["Restore this transcript"].waitForExistence(timeout: 5)); saveScreenshot(app, name: "Audit120-conversation-revisions")
        app.buttons["Restore this transcript"].firstMatch.tap(); app.buttons["Restore transcript"].tap()
        XCTAssertTrue(app.staticTexts["transcript-restore-status"].waitForExistence(timeout: 10))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Original branch answer"].waitForExistence(timeout: 8)); XCTAssertFalse(app.buttons["Stop response"].exists)
        saveScreenshot(app, name: "Audit120-restored-transcript")
    }
    func testAudit120ArchiveInspectionAndIsolatedRestore() {
        let app = productApp("recovery")
        app.buttons["History"].tap(); app.buttons["Settings & access"].tap(); app.buttons["Privacy & recovery"].tap(); app.buttons["Data & recovery"].tap()
        let restore = app.buttons["Restore to a separate library"]
        for _ in 0..<9 { if restore.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(restore.waitForExistence(timeout: 8)); restore.tap()
        XCTAssertTrue(app.staticTexts["Restored library verified"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Use restored library on next launch"].exists)
        saveScreenshot(app, name: "Audit120-verified-separate-library")
    }
    func testAudit120InboxFiltersAndRemovedNoteRecovery() {
        let app = productApp("inbox")
        app.buttons["History"].tap(); app.buttons["sidebar-inbox"].tap()
        let field = app.textFields["inbox-note"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Synthetic note to keep")
        app.buttons["inbox-save"].tap()
        let saved = app.staticTexts["Synthetic note to keep"]; XCTAssertTrue(saved.waitForExistence(timeout: 5))
        for _ in 0..<4 { if app.buttons["Mark handled"].isHittable { break }; app.swipeUp() }
        app.buttons["Mark handled"].tap(); app.buttons["Filed"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5)); saveScreenshot(app, name: "Audit120-filed-inbox-note")
    }

    func testAudit120LargestTextKeepsPrimaryActionsReachable() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty", "--ui-largest", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); XCTAssertTrue(app.buttons["Choose model"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Add to message"].isHittable); XCTAssertTrue(app.buttons["Dictate message"].isHittable)
        app.buttons["Choose model"].tap(); XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["Done"].isHittable)
        saveScreenshot(app, name: "Audit120-largest-text-models")
        app.buttons["Done"].tap(); XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 5))
        app.buttons["History"].tap(); XCTAssertTrue(app.buttons["sidebar-settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sidebar-settings"].isHittable); XCTAssertTrue(app.buttons["sidebar-models"].isHittable)
        saveScreenshot(app, name: "Audit120-largest-text-sidebar")
    }
    func testAudit120ChartCategoryShowsEverySeriesAndDataTable() {
        let app = productApp("charts")
        let picker = app.buttons["chart-category-picker"]
        for _ in 0..<6 { if picker.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap(); app.buttons["Shared"].tap()
        XCTAssertTrue(app.staticTexts["Shared · First: 10"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["Shared · Second: 20"].exists)
        let table = app.buttons["Data table"]; for _ in 0..<4 { if table.isHittable { break }; app.swipeUp() }; table.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Shared · Second")).firstMatch.exists)
        saveScreenshot(app, name: "Audit120-chart-all-series")
    }
    func testAudit120ArchiveExportShowsCoverageBeforeSaving() {
        let app = productApp("export")
        app.buttons["History"].tap(); app.buttons["sidebar-settings"].tap(); app.buttons["Privacy & recovery"].tap(); app.buttons["Data & recovery"].tap()
        let create = app.buttons["Create archive"]
        for _ in 0..<6 { if create.isHittable { break }; app.swipeUp() }
        create.tap()
        let review = app.staticTexts["archive-export-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10)); XCTAssertTrue(review.label.contains("0 conversations"))
        let privateToggle = app.switches["Include on-device-only work and drafts"]
        for _ in 0..<5 { if privateToggle.isHittable { break }; app.swipeDown() }
        privateToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["Save prepared archive to Files"].exists)
        for _ in 0..<6 { if create.isHittable { break }; app.swipeUp() }; create.tap()
        XCTAssertTrue(review.waitForExistence(timeout: 10)); XCTAssertTrue(review.label.contains("1 conversations"))
        saveScreenshot(app, name: "Audit120-archive-export-coverage")
    }
    func testAudit120ScenarioSaveConflictKeepsPreviewAndRevertsExplicitly() {
        let app = productApp("surface-conflict")
        XCTAssertTrue(app.buttons["Set exact Minutes"].waitForExistence(timeout: 8))
        app.buttons["Assistant menu"].tap(); app.buttons["Update synthetic surface"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic surface revision saved"].waitForExistence(timeout: 8))
        app.buttons["Set exact Minutes"].tap()
        let field = app.textFields["scenario-exact-value"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "30")
        app.buttons["Apply value"].tap()
        let revert = app.buttons["Revert to saved"]
        for _ in 0..<5 { if revert.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(revert.waitForExistence(timeout: 8)); XCTAssertTrue(app.staticTexts["Unsaved changes · displayed result is a preview"].exists)
        saveScreenshot(app, name: "Audit120-surface-save-conflict")
        revert.tap(); XCTAssertTrue(app.staticTexts["Points, 70"].waitForExistence(timeout: 8)); XCTAssertFalse(app.buttons["Stop response"].exists)
    }
    func testReplyBudget131LargestSelectionShowsNormalReplyCapacity() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-computer-account", "--ui-reply-budget131", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Response settings"].waitForExistence(timeout: 15))
        app.buttons["Response settings"].tap()
        let reply = app.descendants(matching: .any)["connected-reply-allowance"].firstMatch
        for _ in 0..<10 { if reply.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(reply.exists)
        XCTAssertEqual(reply.value as? String, "Up to 128,000 tokens")
        XCTAssertTrue(app.staticTexts["598,931 tokens"].exists)
        XCTAssertTrue(app.staticTexts["256,685 tokens"].exists)
        XCTAssertTrue(app.staticTexts["Per model response, not for the whole task. Long tasks continue across responses and compactions. Images and tools also use context; the connection enforces its limits."].exists)
        saveScreenshot(app, name: "ReplyBudget131-855K-with-full-reply-room")
    }
    func testContinuity130ReserveAndMobileFallbackAreVisible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-computer-account", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Response settings"].waitForExistence(timeout: 15))
        app.buttons["Response settings"].tap()
        let reserve = app.staticTexts["Compaction reserve · 30%"]
        for _ in 0..<10 { if reserve.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(reserve.exists)
        XCTAssertTrue(app.staticTexts["Active working context"].exists)
        saveScreenshot(app, name: "Continuity130-context-reserve")
        app.navigationBars["Response settings"].buttons["Cancel"].tap()
        app.buttons["Choose model"].tap(); app.buttons["model-account-details"].tap()
        let mobile = app.buttons["Connect mobile ChatGPT"]
        for _ in 0..<6 { if mobile.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(mobile.exists)
        saveScreenshot(app, name: "Continuity130-mobile-fallback")
    }
    func testContinuity130EarlierResultOpensWithoutLosingLaterMessages() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-late-result", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let result = app.buttons["earlier-computer-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 15)); result.tap()
        XCTAssertTrue(app.staticTexts["The earlier report is now ready."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Stop response"].exists)
        saveScreenshot(app, name: "Continuity130-earlier-result")
        app.buttons["Jump to latest message"].tap()
        XCTAssertTrue(app.staticTexts["Later answer 65 stays saved."].waitForExistence(timeout: 8))
        saveScreenshot(app, name: "Continuity130-later-messages-kept")
    }
    func testContinuity130MobileIdentityDoesNotDisplayTheUnavailableComputerAccount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-computer-account", "--ui-mobile-fallback", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose model"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["ChatGPT · mobile connection"].exists)
        XCTAssertFalse(app.buttons["home-chatgpt-sign-in"].exists)
        app.buttons["Choose model"].tap(); app.buttons["model-account-details"].tap()
        XCTAssertTrue(app.staticTexts["mobile@example.test"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["fixture@example.test"].exists)
        saveScreenshot(app, name: "Continuity130-mobile-route-identity")
    }
    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
