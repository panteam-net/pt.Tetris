import XCTest

final class TetrisDuelUITests: XCTestCase {
    func testSoloStartsAndPauses() {
        let app = XCUIApplication(); app.launch()
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
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["menu-host"].exists)
        XCTAssertTrue(app.buttons["menu-join"].exists)
    }
    func testSharedDeviceModeOnIPad() throws {
        let app = XCUIApplication(); app.launch()
        guard app.buttons["menu-shared"].exists else { throw XCTSkip("Shared-device mode is iPad-only.") }
        app.buttons["menu-shared"].tap()
        XCTAssertTrue(app.staticTexts["player-0-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["player-1-name"].exists)
    }
}
