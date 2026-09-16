import XCTest

final class DiaryIntegrationUITests: XCTestCase {
    @MainActor func testIndependentEmotionAndCalendarMarkers() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MOOD_UI_TESTING"] = "1"
        app.launchArguments = ["-app.language", "ru", "-health.sleep.enabled", "NO"]
        app.launch()
        let diary = app.buttons["Дневник"].firstMatch
        if diary.waitForExistence(timeout: 10) { diary.tap() }
        else { app.staticTexts["Дневник"].firstMatch.tap() }
        let add = app.buttons["Добавить запись"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        app.buttons["✨ Эмоции"].tap()
        XCTAssertFalse(app.buttons["Сохранить"].isEnabled)
        app.buttons["Тревожная"].tap()
        app.buttons["Интересно"].tap()
        app.buttons["Сохранить"].tap()
        XCTAssertTrue(app.staticTexts["Общий график"].waitForExistence(timeout: 5))
        add.tap()
        app.buttons["💊 Поддержка"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Не принято")).firstMatch.tap()
        app.buttons["Сохранить"].tap()
        add.tap()
        app.buttons["🌸 Цикл"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Начало менструации")).firstMatch.tap()
        app.buttons["Месяц"].tap()
        // The calendar lies below the common timeline; both markers share one cell.
        let cell = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Не принято", "менструация")).firstMatch
        for _ in 0..<8 where !cell.isHittable { app.swipeUp() }
        XCTAssertTrue(cell.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Calendar with both markers"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}
