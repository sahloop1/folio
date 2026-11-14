import XCTest

final class FolioUITests: XCTestCase {
    @MainActor
    func testCreateTypeAndReopenNotebook() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-library"]
        app.launch()
        let create = app.buttons["new-notebook"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        create.tap()
        let title = app.textFields["notebook-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap(); title.typeText("Native smoke notebook")
        app.buttons["save-notebook"].tap()
        let typing = app.buttons["toggle-typing"]
        XCTAssertTrue(typing.waitForExistence(timeout: 10))
        typing.tap()
        let pageText = app.textViews["page-text"]
        XCTAssertTrue(pageText.waitForExistence(timeout: 10))
        pageText.tap(); pageText.typeText("An offline note that survives relaunch.")
        typing.tap()
        // Backgrounding exercises the app's explicit final-save path.
        XCUIDevice.shared.press(.home)
        app.activate()
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let book = app.buttons["notebook-Native smoke notebook"]
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()
        XCTAssertTrue(app.buttons["toggle-typing"].waitForExistence(timeout: 10))
        app.buttons["toggle-typing"].tap()
        XCTAssertTrue(pageText.waitForExistence(timeout: 10))
        XCTAssertTrue((pageText.value as? String ?? "").contains("survives relaunch"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native Folio on iPad Simulator"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
