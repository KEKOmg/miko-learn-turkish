import Foundation
import UserNotifications

/// Owns the single repeating daily-learning notification used by Settings
/// and onboarding. Calling `update` is idempotent: the previous request is
/// always replaced with the latest user choice.
enum DailyReminderScheduler {
    private static let identifier = "daily-goal-reminder"

    static func update(enabled: Bool, time: Date, soundEnabled: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard enabled else { return false }

        do {
            let currentSettings = await center.notificationSettings()
            let authorized: Bool
            switch currentSettings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                authorized = true
            case .notDetermined:
                authorized = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            case .denied:
                authorized = false
            @unknown default:
                authorized = false
            }
            guard authorized else { return false }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification.dailyGoal.title")
            content.body = String(localized: "notification.dailyGoal.body")
            content.sound = soundEnabled ? .default : nil

            let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: true
            )
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
