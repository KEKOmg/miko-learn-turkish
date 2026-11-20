import UIKit

/// Centralized haptic feedback. Respects `UserSettings.hapticsEnabled` when
/// the caller passes a setting; otherwise uses the system default. No-ops
/// gracefully on devices without a Taptic Engine (UIKit handles this).
enum Haptics {

    /// A sharp impact used when the user loses a heart.
    static func heartLost(enabled: Bool = true) {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }

    /// A success notification used when an achievement is earned.
    static func achievementEarned(enabled: Bool = true) {
        guard enabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// A light selection tap for generic button presses.
    static func selection(enabled: Bool = true) {
        guard enabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
