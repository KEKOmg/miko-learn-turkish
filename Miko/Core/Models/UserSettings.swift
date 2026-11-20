import Foundation
import SwiftData

@Model
final class UserSettings {
    @Attribute(.unique) var id: UUID
    var interfaceLanguage: String
    var audioEnabled: Bool
    var hapticsEnabled: Bool
    var notificationsEnabled: Bool
    var soundOn: Bool
    var reduceMotion: Bool
    var dailyGoalReminderTime: Date?

    var user: UserProfile?

    init(
        id: UUID = UUID(),
        interfaceLanguage: String = "ru",
        audioEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        notificationsEnabled: Bool = false,
        soundOn: Bool = true,
        reduceMotion: Bool = false,
        dailyGoalReminderTime: Date? = nil,
        user: UserProfile? = nil
    ) {
        self.id = id
        self.interfaceLanguage = interfaceLanguage
        self.audioEnabled = audioEnabled
        self.hapticsEnabled = hapticsEnabled
        self.notificationsEnabled = notificationsEnabled
        self.soundOn = soundOn
        self.reduceMotion = reduceMotion
        self.dailyGoalReminderTime = dailyGoalReminderTime
        self.user = user
    }
}
