import UIKit
import AudioToolbox

final class FeedbackService: FeedbackServing {
    var isEnabled: Bool {
        get { !defaults.bool(forKey: "feedbackMuted") }
        set { defaults.set(!newValue, forKey: "feedbackMuted") }
    }
    private let defaults: UserDefaults
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()
    init(defaults: UserDefaults) { self.defaults = defaults }
    func play(_ effect: GameEffect) {
        guard isEnabled else { return }
        switch effect {
        case .lock, .hold: impact.impactOccurred(intensity: 0.45)
        case .clear: notification.notificationOccurred(.success); AudioServicesPlaySystemSound(1104)
        case .garbage: notification.notificationOccurred(.warning)
        case .win: notification.notificationOccurred(.success); AudioServicesPlaySystemSound(1025)
        }
    }
}
