import XCTest

final class ReaderFlowTests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    @MainActor private func prepare() {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-showThumbnails", "YES", "-showPageNumbers", "YES", "-readerFullscreen", "NO", "-pageCurl", "NO", "-appLock", "NO", "-pageLayout", "grid"]
    }
    @MainActor private func openReader() {
        prepare(); app.launch()
        openBook()
        let page = app.buttons["book.page.Lecture 1"]
        XCTAssertTrue(page.waitForExistence(timeout: 10)); page.tap()
        XCTAssertTrue(app.images["reader.image"].waitForExistence(timeout: 15))
    }
    @MainActor private func openBook() {
        let book = app.buttons["library.book.Physics"]
        for _ in 0..<10 {
            if book.exists && book.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(book.isHittable); book.tap()
    }
    @MainActor private func openTool(_ title: String, navigationTitle: String) {
        app.buttons["reader.menu"].tap()
        let action = app.buttons[title].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5)); action.tap()
        XCTAssertTrue(app.navigationBars[navigationTitle].waitForExistence(timeout: 8), "Empty sheet for \(title)")
    }
    @MainActor func testImageAndTextKeepTheirReadingArea() {
        openReader()
        let image = app.images["reader.image"]
        XCTAssertGreaterThan(image.frame.height, app.windows.firstMatch.frame.height * 0.45)
        XCTAssertLessThan(image.frame.maxY, app.buttons["reader.thumbnail.0"].frame.minY + 8)
        app.segmentedControls.firstMatch.buttons.element(boundBy: 1).tap()
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Energy is conserved.")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5)); XCTAssertTrue(text.isHittable)
        XCTAssertLessThan(text.frame.maxY, app.buttons["reader.thumbnail.0"].frame.minY)
        app.segmentedControls.firstMatch.buttons.element(boundBy: 0).tap()
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["3 of 4"].waitForExistence(timeout: 5))
    }
    @MainActor func testEveryReaderToolOpensOnFirstTap() {
        openReader()
        let tools = [
            ("Annotate", "Annotate", "Cancel"),
            ("Crop & enhance", "Crop & enhance", "Cancel"),
            ("Revision mode", "Revision", "Close"),
            ("Move", "Move 1 page", "Cancel"),
            ("Related pages", "Related pages", "Done"),
            ("Version history", "Version history", "Done"),
            ("Insert paper after", "Paper", "Cancel")
        ]
        for (action, title, close) in tools {
            openTool(action, navigationTitle: title)
            switch action {
            case "Annotate":
                let save = app.navigationBars[title].buttons["Save"]
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
            case "Crop & enhance": XCTAssertTrue(app.images["enhancement.preview"].waitForExistence(timeout: 15))
            case "Revision mode":
                app.buttons["Add cover"].tap()
                XCTAssertTrue(app.buttons["Covered answer"].exists)
            case "Version history": XCTAssertTrue(app.staticTexts["Original scan"].exists)
            case "Insert paper after": XCTAssertTrue(app.buttons["Lined"].exists)
            default: break
            }
            app.navigationBars[title].buttons[close].tap()
            XCTAssertTrue(app.buttons["reader.menu"].waitForExistence(timeout: 5))
        }
    }
    @MainActor func testOCRIsEditedInsideReader() {
        openReader()
        app.buttons["Edit page"].tap()
        XCTAssertTrue(app.textFields["Page title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["Recognised text"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["reader.menu"].exists)
    }
    @MainActor func testDividerIsAReaderPage() {
        prepare(); app.launch()
        openBook()
        app.buttons["book.divider.Mechanics"].tap()
        XCTAssertTrue(app.navigationBars["Mechanics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 of 4"].exists)
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.images["reader.image"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["2 of 4"].exists)
    }
    @MainActor func testSelectionExportsMultiplePagesFromReader() {
        openReader()
        app.buttons["reader.menu"].tap(); app.buttons["Select pages"].tap()
        app.buttons["reader.thumbnail.2"].tap()
        let share = app.buttons["reader.exportSelection"]
        XCTAssertTrue(share.label.contains("2")); share.tap()
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 15), "Native PDF share sheet must open")
    }
    @MainActor func testAddPagesStartsWithCompactSourceToolbar() {
        prepare(); app.launch(); app.buttons["library.addPages"].tap()
        for id in ["capture.scan", "capture.photos", "capture.files"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
        }
        XCTAssertGreaterThan(app.buttons["capture.photos"].frame.minY, app.windows.firstMatch.frame.height * 0.55)
        XCTAssertFalse(app.navigationBars["Add pages"].exists)
    }
    @MainActor func testImportedBatchPromptsForDestinationAfterSaving() {
        prepare(); app.launchArguments.append("-ui-test-import")
        app.launch(); app.buttons["library.addPages"].tap()
        XCTAssertTrue(app.navigationBars["Add 1 page"].waitForExistence(timeout: 20))
        app.buttons["Keep in Unfiled"].tap()
        let unfiled = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Unfiled")).firstMatch
        for _ in 0..<10 {
            if unfiled.exists && unfiled.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(unfiled.waitForExistence(timeout: 5)); unfiled.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Physics lecture")).firstMatch.waitForExistence(timeout: 15))
    }
}
