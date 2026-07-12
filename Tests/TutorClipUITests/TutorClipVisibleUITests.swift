import XCTest

final class TutorClipVisibleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TUTORCLIP_UI_TEST"] = "1"
        app.launchEnvironment["TUTORCLIP_UI_TEST_DIRECTORY"] = NSTemporaryDirectory()
            + "TutorClipVisibleUITests-\(UUID().uuidString)"
        app.launch()
    }

    override func tearDownWithError() throws {
        // Keep the target visible after the run so a person watching the UI can
        // inspect the final state or the exact failure instead of seeing a window vanish.
        app = nil
    }

    func testVisibleLaunchOpensTodayPractice() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(element("sidebar.today").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["今日学习"].waitForExistence(timeout: 3), app.debugDescription)
    }

    func testVisibleCommandCommaOpensAndClosesSettings() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["帮助与设置"].waitForExistence(timeout: 3), app.debugDescription)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 3))
    }

    func testVisibleSettingsPrivacyControlsPersistAndCanBeRestored() throws {
        app.typeKey(",", modifierFlags: .command)
        let learningProgress = element("settings.learningProgress")
        let history = element("settings.history")
        let save = element("settings.save")
        XCTAssertTrue(learningProgress.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(history.exists)

        learningProgress.click()
        history.click()
        save.click()
        XCTAssertTrue(app.staticTexts["设置已保存。"].waitForExistence(timeout: 3), app.debugDescription)

        learningProgress.click()
        history.click()
        save.click()
        XCTAssertTrue(app.staticTexts["设置已保存。"].waitForExistence(timeout: 3))
    }

    func testVisibleLearningWorkflow() throws {
        let questionRoute = element("sidebar.question")
        XCTAssertTrue(questionRoute.waitForExistence(timeout: 5))
        questionRoute.click()

        let wrongAnswer = element("answer.A")
        XCTAssertTrue(wrongAnswer.waitForExistence(timeout: 3), app.debugDescription)
        wrongAnswer.click()

        let retry = element("answer.retry")
        // The retry affordance is the user-visible incorrect-answer state. It is
        // more stable than asserting the internal label's accessibility node.
        XCTAssertTrue(retry.waitForExistence(timeout: 3), app.debugDescription)
        retry.click()
        element("answer.B").click()
        XCTAssertTrue(element("answer.result.correct").waitForExistence(timeout: 2))
        XCTAssertFalse(element("answer.retry").exists)

        element("sidebar.vocabulary").click()
        let search = element("vocabulary.search")
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("cohesion")
        XCTAssertTrue(app.staticTexts["cohesion"].waitForExistence(timeout: 2))

        let edit = element("vocabulary.edit.cohesion")
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.click()
        let meaning = element("vocabulary.editor.meaning")
        XCTAssertTrue(meaning.waitForExistence(timeout: 2))
        meaning.click()
        meaning.typeKey("a", modifierFlags: .command)
        meaning.typeText("社区凝聚力")
        element("vocabulary.editor.save").click()
        XCTAssertTrue(app.staticTexts["社区凝聚力"].waitForExistence(timeout: 2))

        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        let showAnswer = element("vocabulary.showAnswer")
        XCTAssertTrue(showAnswer.waitForExistence(timeout: 3))
        showAnswer.click()
        let known = element("vocabulary.review.known")
        XCTAssertTrue(known.waitForExistence(timeout: 2))
        known.click()

        element("sidebar.question").click()
        let nextQuestion = element("adaptive.nextQuestion")
        XCTAssertTrue(nextQuestion.waitForExistence(timeout: 3))
        nextQuestion.click()
        let nextAnswer = element("answer.A")
        XCTAssertTrue(nextAnswer.waitForExistence(timeout: 4))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: nextAnswer)
        waitForExpectations(timeout: 4)

        let needsReview = element("studyStatus.needsReview")
        XCTAssertTrue(needsReview.waitForExistence(timeout: 2))
        needsReview.click()
        let applicationGap = element("needsReview.gap.application")
        XCTAssertTrue(applicationGap.waitForExistence(timeout: 2))
        applicationGap.click()
        XCTAssertTrue(element("needsReview.startLearning").waitForExistence(timeout: 2))

        element("sidebar.history").click()
        XCTAssertTrue(app.staticTexts["历史"].waitForExistence(timeout: 3))
        element("sidebar.knowledge").click()
        XCTAssertTrue(app.staticTexts["知识图谱"].waitForExistence(timeout: 3))
        element("sidebar.today").click()
        XCTAssertTrue(app.staticTexts["今日学习"].waitForExistence(timeout: 3))
    }

    func testVisibleCommandWClosesOnlyTheWindow() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        app.typeKey("w", modifierFlags: .command)

        expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: app.windows)
        waitForExpectations(timeout: 3)
        XCTAssertNotEqual(app.state, .notRunning)
    }

    func testVisibleCommandQTerminatesTheApp() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        app.typeKey("q", modifierFlags: .command)

        XCTAssertTrue(app.wait(for: .notRunning, timeout: 3))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

}
