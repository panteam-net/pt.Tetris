import XCTest
#if SWIFT_PACKAGE
@testable import TetrisCore
#else
@testable import pt_TetrisDuel
#endif

final class WireTests: XCTestCase {
    private func state() -> MatchSnapshot {
        let match = Match(seed: 42, players: 2)
        return MatchSnapshot(round: 3, revision: 123, phase: .playing, countdown: 0, elapsed: 12.5,
                             boards: match.boards.map { $0.snapshot }, wins: [1, 2], winner: nil)
    }
    
    func testSnapshotRoundTripAndSize() throws {
        let message = WireMessage.snapshot(state()), data = try WireCodec.encode(message)
        XCTAssertLessThan(data.count, 320)
        XCTAssertEqual(try WireCodec.decode(data), message)
    }
    
    func testAllCommandsRoundTrip() throws {
        let messages: [WireMessage] = [.ready, .heartbeat, .bye,
            .input(round: 5, sequence: 23, action: .hardDrop, pressed: true),
            .pause(round: 5, paused: false), .availability(false), .rematch(round: 5)]
        for message in messages { XCTAssertEqual(try WireCodec.decode(WireCodec.encode(message)), message) }
    }
    
    func testRejectsTruncatedTrailingAndWrongVersionPackets() throws {
        let data = try WireCodec.encode(.snapshot(state()))
        for count in 0..<data.count { XCTAssertThrowsError(try WireCodec.decode(Data(data.prefix(count)))) }
        XCTAssertThrowsError(try WireCodec.decode(data + Data([0])))
        var bad = data; bad[0] = 200
        XCTAssertThrowsError(try WireCodec.decode(bad))
        XCTAssertThrowsError(try WireCodec.decode(Data(repeating: 0, count: 1025)))
    }
    
    func testRejectsInvalidCellsAndRotation() throws {
        var bad = state(); bad.boards[0].grid[0] = 15
        XCTAssertThrowsError(try WireCodec.encode(.snapshot(bad)))
        bad = state(); bad.boards[0].piece.rotation = 7
        XCTAssertThrowsError(try WireCodec.decode(WireCodec.encode(.snapshot(bad))))
    }
    
    func testRejectsUnknownActionsAndBooleanValues() {
        XCTAssertThrowsError(try WireCodec.decode(Data([1, 7, 2])))
        XCTAssertThrowsError(try WireCodec.decode(Data([1, 5, 0,0,0,1, 0,0,0,1, 99, 1])))
    }
}
