import XCTest

final class TetrisDuelUITests: XCTestCase {
    private func application(language: String = "en") -> XCUIApplication {
        let result = XCUIApplication()
        result.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ru" ? "ru_RU" : "en_US"
        ]
        result.launch()
        return result
    }

    func testSoloStartsAndPauses() {
        let app = application()
        app.buttons["menu-solo"].tap()
        XCTAssertTrue(app.staticTexts["player-0-name"].waitForExistence(timeout: 5))
        let pause = app.navigationBars.buttons["Pause or resume"]
        XCTAssertTrue(pause.exists)
        pause.tap()
        XCTAssertTrue(app.staticTexts["PAUSED"].waitForExistence(timeout: 2))
        app.buttons["game-primary"].tap()
        XCTAssertFalse(app.staticTexts["PAUSED"].exists)
    }
    
    func testNearbyMenuIsAvailable() {
        let app = application()
        XCTAssertTrue(app.buttons["menu-host"].exists)
        XCTAssertTrue(app.buttons["menu-join"].exists)
    }
    
    func testSharedDeviceModeOnIPad() throws {
        let app = application()
        guard app.buttons["menu-shared"].exists else { throw XCTSkip("Shared-device mode is iPad-only.") }
        app.buttons["menu-shared"].tap()
        XCTAssertTrue(app.staticTexts["player-0-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["player-1-name"].exists)
    }

    func testRussianMenuAndGameAreLocalized() {
        continueAfterFailure = false
        let app = application(language: "ru")
        XCTAssertEqual(app.buttons["menu-solo"].label, "Одиночная игра")
        XCTAssertEqual(app.buttons["menu-host"].label, "Создать игру рядом")
        XCTAssertEqual(app.buttons["menu-join"].label, "Найти игру рядом")
        app.buttons["menu-solo"].tap()
        XCTAssertTrue(
            app.staticTexts["player-0-name"].waitForExistence(timeout: 5)
        )
        XCTAssertEqual(app.staticTexts["player-0-name"].label, "ВЫ")
        app.navigationBars.buttons["game-pause"].tap()
        XCTAssertEqual(app.staticTexts["game-overlay-title"].label, "ПАУЗА")
        XCTAssertEqual(app.buttons["game-primary"].label, "Продолжить")
        app.navigationBars.buttons["game-help"].tap()
        XCTAssertTrue(app.alerts["Как играть"].exists)
        XCTAssertTrue(app.alerts.buttons["Понятно"].exists)
    }
}
