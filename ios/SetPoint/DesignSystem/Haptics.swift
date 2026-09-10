import UIKit

/// Small, sparing haptics (§5a restraint — "manager, not punisher"). Fired only
/// on moments the app itself initiates or confirms: a check-in opening, a meal
/// logged, a weigh-in saved. Never on scroll, dismiss, or plain navigation.
enum Haptics {
    /// A light tap — the app is asking for attention (check-in opening).
    static func nudge() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }

    /// A soft success — something the user did just landed (meal logged, weigh-in saved).
    static func landed() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
