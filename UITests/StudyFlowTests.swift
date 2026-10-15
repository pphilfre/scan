import XCTest

final class StudyFlowTests: XCTestCase {
    @MainActor private func launch(seed: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-appLock", "NO", "-pageCurl", "NO"] + (seed ? ["-ui-study"] : [])
        app.launch(); return app
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor func testStandalonePaperOpensScansAndQuestionWorkspace() {
        let app = launch()
        app.buttons["library.study.Past Papers"].tap()
        app.buttons["study.record.maths-2025-1"].tap()
        let openScans = app.buttons["Open 3 pages in reader"]
        reveal(openScans, in: app); openScans.tap()
        XCTAssertTrue(app.images["reader.image"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 of 3"].exists)
        app.buttons["Close"].firstMatch.tap()
        let question = app.buttons["study.record.q1a"]
        reveal(question, in: app); question.tap()
        XCTAssertTrue(app.buttons["study.mark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open question scans"].exists)
    }
    @MainActor func testReviewRevealRatingAndSessionSummary() {
        let app = launch()
        app.buttons["library.study.Flashcards & review"].tap()
        app.buttons["Start a study session"].tap()
        app.buttons["study.session.start"].tap()
        XCTAssertTrue(app.buttons["study.review.reveal"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["study.rate.Got it"].exists)
        app.buttons["study.review.reveal"].tap()
        XCTAssertTrue(app.staticTexts["study.review.answer"].exists)
        app.buttons["study.rate.Got it"].tap()
        XCTAssertTrue(app.buttons["study.review.done"].waitForExistence(timeout: 5))
        app.buttons["study.review.done"].tap()
        let finish = app.buttons["study.session.finish"]
        reveal(finish, in: app); finish.tap()
        XCTAssertTrue(app.staticTexts["study.session.summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["study.session.summary"].label.contains("1 card reviewed"))
        app.buttons["study.session.done"].tap()
        XCTAssertFalse(app.buttons["study.review"].isEnabled)
    }
    @MainActor func testQuickMarksSaveAndOfferLearningActions() {
        let app = launch()
        app.buttons["library.study.Past Papers"].tap()
        app.buttons["study.record.maths-2025-1"].tap()
        let question = app.buttons["study.record.q1a"]
        reveal(question, in: app); question.tap()
        app.buttons["study.mark"].tap()
        let earned = app.textFields["study.field.earned"]
        XCTAssertTrue(earned.waitForExistence(timeout: 5))
        earned.tap(); earned.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "3")
        app.buttons["study.save"].tap()
        let retry = app.sheets.buttons["Retry tomorrow"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3 / 3 marks")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Retry scheduled for tomorrow"].exists)
    }
    @MainActor func testImportPreviewRequiresConfirmationAndRepeatSkips() {
        let app = launch(seed: false)
        app.buttons["library.study.Course maps"].tap()
        app.buttons["study.transfer"].tap()
        app.buttons["Format rules and example"].tap()
        let example = app.buttons["Load example into paste area"]
        reveal(example, in: app); example.tap()
        let parse = app.buttons["study.import.parse"]
        reveal(parse, in: app); parse.tap()
        let confirm = app.buttons["study.import.confirm"]
        reveal(confirm, in: app)
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(app.staticTexts["study.import.summary"].label.contains("9 additions"))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["study.import.result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["study.import.result"].label.contains("Import complete"))
        for _ in 0..<12 { if parse.isHittable { break }; app.swipeDown() }
        parse.tap()
        reveal(confirm, in: app)
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(app.staticTexts["study.import.summary"].label.contains("9 skipped"))
    }
}
