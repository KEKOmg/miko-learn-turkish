import Foundation
import SwiftData

@Model
final class UserAchievement {
    @Attribute(.unique) var id: UUID
    var earnedAt: Date
    var progress: Int

    var user: UserProfile?
    var achievement: Achievement?

    init(
        id: UUID = UUID(),
        earnedAt: Date = .now,
        progress: Int = 0,
        user: UserProfile? = nil,
        achievement: Achievement? = nil
    ) {
        self.id = id
        self.earnedAt = earnedAt
        self.progress = progress
        self.user = user
        self.achievement = achievement
    }
}