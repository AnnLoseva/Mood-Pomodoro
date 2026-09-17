import XCTest

final class AnalyticsTabUITests: XCTestCase {
    @MainActor
    func testAnalyticsTabOpens() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Позже"].waitForExistence(timeout: 6) {
            app.buttons["Позже"].tap()
        }
        let tab = app.tabBars.buttons["Аналитика"].firstMatch
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
        } else {
            app.cells["Аналитика"].firstMatch.tap()
        }
        XCTAssertTrue(
            app.buttons["Обзор"].waitForExistence(timeout: 6)
                || app.staticTexts["Пока мало данных"].waitForExistence(timeout: 2)
        )
    }
}
