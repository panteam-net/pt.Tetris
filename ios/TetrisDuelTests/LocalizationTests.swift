import XCTest
@testable import pt_TetrisDuel

final class LocalizationTests: XCTestCase {
    func testRussianLocalNetworkPromptIsBundled() throws {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: "ru", ofType: "lproj")
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        let result = bundle.localizedString(
            forKey: "NSLocalNetworkUsageDescription",
            value: nil,
            table: "InfoPlist"
        )
        XCTAssertEqual(
            result,
            "Поиск и подключение к игроку рядом по Wi-Fi для дуэли."
        )
    }

    func testFormattingPreservesPlayerNameAndPercentSigns() {
        let name = "Ирина 50% %@"
        let result = L10n.format("lobby.invitation.title", name)
        XCTAssertTrue(result.contains(name))
        XCTAssertNotEqual(result, "lobby.invitation.title")
    }
}
