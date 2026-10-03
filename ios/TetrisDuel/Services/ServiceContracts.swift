import Foundation

struct NearbyPeer: Equatable {
    let id: String
    let name: String
}

enum NearbyRole { case host, guest }
enum NearbyEvent {
    case status(String)
    case peers([NearbyPeer])
    case invitation(name: String, answer: (Bool) -> Void)
    case connected(name: String)
    case disconnected(String)
    case failure(String)
}

/// Implementations deliver callbacks on the main thread. They have one owner:
/// the lobby, followed by the game interactor after a successful connection.
protocol NearbyTransport: AnyObject {
    var onEvent: ((NearbyEvent) -> Void)? { get set }
    var onMessage: ((WireMessage) -> Void)? { get set }
    var isConnected: Bool { get }
    func host()
    func browse()
    func invite(_ peer: NearbyPeer)
    func send(_ message: WireMessage) throws
    func disconnect()
}

protocol GameClock: AnyObject {
    var onTick: ((Double) -> Void)? { get set }
    var now: TimeInterval { get }
    func start()
    func stop()
}

protocol FeedbackServing: AnyObject {
    var isEnabled: Bool { get set }
    func play(_ effect: GameEffect)
}

protocol SeedProviding { func next() -> UInt64 }
struct SystemSeedProvider: SeedProviding {
    func next() -> UInt64 { UInt64.random(in: UInt64.min...UInt64.max) }
}
