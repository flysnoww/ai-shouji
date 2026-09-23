import XCTest

final class NavigationRegressionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-regression-tests", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private var record: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "record.")).firstMatch
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAllHomeCardsOpenAndDetailFloats() {
        for module in ["ledger", "todo", "memo", "idea"] {
            let card = app.buttons["home.module.\(module)"]
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            if !card.isHittable { app.swipeUp() }
            card.tap()
            XCTAssertTrue(record.waitForExistence(timeout: 5), module)
            record.tap()
            let close = app.buttons["detail.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(close.frame.minY, app.frame.height * 0.15)
            screenshot("\(module)-floating-detail")
            app.scrollViews.firstMatch.swipeUp()
            XCTAssertTrue(close.isHittable)
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
            XCTAssertTrue(record.isHittable)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testCardEdgeTapAfterDragAndSheetDragDismiss() {
        let card = app.buttons["home.module.ledger"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let center = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.2, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        XCTAssertTrue(card.isHittable)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.3)).tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        let close = app.buttons["detail.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        // Start in the native sheet chrome, outside the scrolling form.
        let handle = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: close.frame.minY - 16))
        handle.press(forDuration: 0.15, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(record.isHittable)
    }

    func testSearchPageTwoSurvivesDetailClose() {
        app.buttons["home.search"].tap()
        let pageTwo = app.buttons["search.page.2"].firstMatch
        for _ in 0..<4 where !pageTwo.isHittable { app.swipeUp() }
        XCTAssertTrue(pageTwo.isHittable)
        pageTwo.tap()
        XCTAssertEqual(app.staticTexts["search.page"].firstMatch.label, "2 / 3")
        record.tap()
        let close = app.buttons["detail.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        screenshot("search-page-two-detail")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["search.page"].firstMatch.label, "2 / 3")
        screenshot("search-page-two-restored")
    }
}
