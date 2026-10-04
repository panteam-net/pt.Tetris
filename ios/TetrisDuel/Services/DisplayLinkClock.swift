import UIKit

final class DisplayLinkClock: NSObject, GameClock {
    var onTick: ((Double) -> Void)?
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var link: CADisplayLink?
    private var previous: CFTimeInterval = 0
    
    private lazy var proxy = DisplayLinkProxy(owner: self)
    
    func start() {
        guard link == nil else { return }
        previous = 0
        let link = CADisplayLink(
            target: proxy,
            selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30,
            maximum: 60,
            preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }
    
    func stop() {
        link?.invalidate()
        link = nil
        previous = 0
    }
    
    fileprivate func tick(_ link: CADisplayLink) {
        let dt = previous == 0 ? 1.0 / 60 : min(0.05, max(0, link.timestamp - previous))
        previous = link.timestamp
        onTick?(dt)
    }
    
    deinit { link?.invalidate() }
}

private final class DisplayLinkProxy: NSObject {
    weak var owner: DisplayLinkClock?
    init(owner: DisplayLinkClock) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}
