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
        app.launchArguments = ["--ui-coherence", "--ui-local-controls", "--ui-qwen-memory", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Response settings"].waitForExistence(timeout: 15))
        app.buttons["Response settings"].tap()
        let context = app.descendants(matching: .any).matching(identifier: "local-working-context").firstMatch
        for _ in 0..<5 { if context.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertEqual(context.value as? String, "32,768 tokens")
        XCTAssertFalse(app.staticTexts["0 tokens"].exists)
        let memory = app.buttons["Memory settings"]
        for _ in 0..<4 { if memory.isHittable { break }; app.swipeUp() }
        memory.tap()
        XCTAssertTrue(app.staticTexts["iOS headroom"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Qwen-local-context-and-memory-budget")
        app.navigationBars["Response settings"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Choose model"].exists)
    }
    func testDownloadedModelChooserSeparatesSelectionDetailsAndDownloads() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-coherence", "--ui-local-controls", "--ui-qwen-memory", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        XCTAssertEqual(estimate.value as? String, "32,768 tokens")
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
        app.buttons["Add to message"].tap(); app.buttons["Library"].tap()
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
        XCTAssertEqual(count.value as? String, "10")
        XCTAssertTrue(app.staticTexts["Total, 185"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Interactive-scenario-result")
        let first = app.staticTexts["1+1"]
        for _ in 0..<12 { if first.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(first.isHittable)
        app.buttons["Edit message"].firstMatch.tap()
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
        app.buttons["Add to message"].tap(); app.buttons["Library"].tap()
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
        executionTimeAllowance = 180
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["study-plan.md"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments = ["--ui-library"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home-greeting"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["user-message-text"].exists)
        XCTAssertFalse(app.buttons["Read response aloud"].exists)
        XCTAssertTrue(app.staticTexts["Recently created"].exists)
        app.buttons["Add to message"].tap()
        XCTAssertTrue(app.buttons["Choose files"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Library"].exists)
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
        app.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["sample.csv"].waitForExistence(timeout: 5))
        app.staticTexts["sample.csv"].tap()
        app.buttons["Attach to current chat"].tap()
        print("After Library attachment, app state: \(app.state.rawValue)\n" + app.debugDescription)
        saveScreenshot(app, name: "After-library-attachment")
        XCTAssertTrue(app.staticTexts["sample.csv"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "File-attachment")
        app.buttons["Add to message"].tap()
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
        XCTAssertFalse(app.buttons["New conversation"].exists); XCTAssertFalse(app.buttons["Settings"].exists); XCTAssertFalse(app.buttons["Library"].exists)
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

    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
