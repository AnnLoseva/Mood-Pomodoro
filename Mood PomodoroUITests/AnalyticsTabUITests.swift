import XCTest

final class AnalyticsTabUITests: XCTestCase {
    @MainActor
    func testAnalyticsTabOpensWithoutASectionRow() throws {
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
        // Either the new home (period menu + explore) or the empty state.
        XCTAssertTrue(
            app.buttons["Период"].waitForExistence(timeout: 6)
                || app.staticTexts["Пока мало данных"].waitForExistence(timeout: 2)
        )
        // The old row of six section buttons and the row of period buttons are gone.
        XCTAssertFalse(app.buttons["Обзор"].exists)
        XCTAssertFalse(app.buttons["Сравнение"].exists && app.buttons["Активности"].exists)
    }

    @MainActor
    func testThereIsNoHistoryTab() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Позже"].waitForExistence(timeout: 6) {
            app.buttons["Позже"].tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Дневник"].firstMatch.waitForExistence(timeout: 6)
                      || app.cells["Дневник"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.tabBars.buttons["История"].exists)
        XCTAssertFalse(app.cells["История"].exists)
    }
}
