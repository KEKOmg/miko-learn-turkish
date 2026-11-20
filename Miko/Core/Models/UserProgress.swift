import Foundation
import SwiftData

@Model
final class UserProgress {
    @Attribute(.unique) var id: UUID
    var xp: Int
    var totalLessonsCompleted: Int
    var totalCorrectAnswers: Int
    var totalExercisesAnswered: Int
    /// Soft currency awarded on lesson completion and spent in the Shop
    /// (heart refills, etc.). Additive field — defaults to 0 for rows
    /// created before Phase 6.
    var gems: Int

    var user: UserProfile?
    var streak: Streak?
    var dailyGoal: DailyGoal?

    init(
        id: UUID = UUID(),
        xp: Int = 0,
        totalLessonsCompleted: Int = 0,
        totalCorrectAnswers: Int = 0,
        totalExercisesAnswered: Int = 0,
        gems: Int = 0
    ) {
        self.id = id
        self.xp = xp
        self.totalLessonsCompleted = totalLessonsCompleted
        self.totalCorrectAnswers = totalCorrectAnswers
        self.totalExercisesAnswered = totalExercisesAnswered
        self.gems = gems
    }
}