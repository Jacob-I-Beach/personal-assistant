import XCTest

@MainActor
final class AssistantUITests: XCTestCase {
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
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "question-answer").firstMatch.value as? String, "Afternoon")
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
        let activity = app.staticTexts["Activity"].firstMatch
        for _ in 0..<5 { if activity.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(activity.isHittable); activity.tap()
        let history = app.staticTexts["Earlier conversations & files · 5"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
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
        XCTAssertTrue(app.staticTexts["The saved route is ready. Open it when you’re ready."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Continue reply"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Prepare an example walking route").count, 1)
        app.buttons["Assistant menu"].tap(); app.buttons["Library"].tap()
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
        let before = row.frame.minY
        row.tap()
        XCTAssertTrue(app.staticTexts["Example reference"].waitForExistence(timeout: 5))
        row.tap()
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
        XCTAssertTrue(app.switches["Use location while I’m here"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use my approximate location"].exists)
        saveScreenshot(app, name: "Home-context-controls")
        app.navigationBars["Home context"].buttons["Done"].tap()
        app.navigationBars["Connections"].buttons["Done"].tap()
        for _ in 0..<4 { if app.buttons["Work with files"].isHittable { break }; app.swipeDown() }
        app.buttons["Work with files"].tap()
        let picker = NSPredicate { _, _ in app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].exists || (app.navigationBars["Recents"].exists && app.buttons["Browse"].exists) }
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
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-demo", "--ui-workspace", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let thinking = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Thinking effort,")).firstMatch
        XCTAssertTrue(thinking.waitForExistence(timeout: 15)); thinking.tap()
        for title in ["Low", "Medium", "High", "Extra High", "Max"] {
            if !app.staticTexts[title].exists { app.swipeUp() }
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
        }
        saveScreenshot(app, name: "Thinking-effort")
        app.staticTexts["High"].tap()
        XCTAssertTrue(app.buttons["Thinking effort, High"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["Add to message"].waitForExistence(timeout: 15))
        app.buttons["Add to message"].tap(); app.buttons["Connected folders"].tap()
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
        app.buttons["Assistant menu"].tap(); app.buttons["Library"].tap()
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
        XCTAssertTrue(app.staticTexts["I’ll check the reference values, then calculate the circumference."].exists)
        XCTAssertTrue(app.staticTexts["No observations were supplied, so I’ll use an illustrative example."].exists)
        XCTAssertFalse(app.buttons["Read response aloud"].isHittable)
        saveScreenshot(app, name: "Response-progress-and-web")
        app.staticTexts["Searched the web"].tap()
        XCTAssertTrue(app.staticTexts["Example reference"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Response-web-sources")
        app.staticTexts["Searched the web"].tap()
        let activity = app.staticTexts["Activity"].firstMatch
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
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Qwen 3.5 4B"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "Model-library")
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
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        composer.typeText("A synthetic message long enough to wrap naturally across the full width of the input.")
        XCTAssertGreaterThan(composer.frame.width, app.frame.width * 0.78)
        saveScreenshot(app, name: "Full-width-composer")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["Your synthetic request started without another connection prompt."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Allow for this conversation"].exists)
        let actions = app.descendants(matching: .any).matching(identifier: "final-response-actions").allElementsBoundByIndex.last!
        actions.buttons["Copy message"].tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2))
        saveScreenshot(app, name: "Copied-confirmation")
        app.buttons["Choose model"].tap(); app.buttons["Working context"].tap()
        for _ in 0..<4 { if app.buttons["1,000,000 tokens"].isHittable { break }; app.swipeUp() }
        app.buttons["1,000,000 tokens"].tap()
        saveScreenshot(app, name: "Model-context-million")
        app.buttons["Save"].tap(); app.buttons["Done"].tap()
        app.buttons["Choose model"].tap(); app.buttons["Working context"].tap()
        XCTAssertTrue(app.navigationBars["Working context"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap(); app.buttons["Done"].tap()
        XCTAssertFalse(app.alerts["Could not finish"].exists)
        app.buttons["Assistant menu"].tap()
        XCTAssertFalse(app.buttons["New conversation"].exists); XCTAssertFalse(app.buttons["Settings"].exists)
        saveScreenshot(app, name: "Focused-chat-menu")
    }

    func testToolExpansionAndLatestButtonPreserveIntentionalPosition() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-long-task", "--ui-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 15))
        let group = app.staticTexts["Activity"].firstMatch
        for _ in 0..<5 { if group.isHittable { break }; app.swipeDown() }
        let before = group.frame.minY; group.tap()
        XCTAssertLessThan(abs(group.frame.minY - before), 5)
        let category = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Earlier conversations & files")).firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.tap()
        let row = app.staticTexts["Read saved context"].firstMatch
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
        XCTAssertTrue(app.staticTexts["The current request is complete."].isHittable)
    }

    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
