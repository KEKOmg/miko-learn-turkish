import Foundation

/// Formalizes the condition encoded in `Achievement.conditionTypeRaw`. The
/// engine maps each case to a predicate over the user's gamification state.
enum AchievementConditionType: String, CaseIterable, Sendable {
    /// `totalLessonsCompleted >= conditionValue`
    case lessonsCompleted = "lessonsCompleted"
    /// `currentStreak >= conditionValue`
    case streak = "streak"
    /// `xp >= conditionValue`
    case xp = "xp"
    /// `perfectLessonCount >= conditionValue` (accuracy == 1.0 on a run)
    case perfectLesson = "perfectLesson"

    /// Resolves from the raw string stored on `Achievement`; returns `nil`
    /// for unknown conditions so malformed seed data is ignored gracefully
    /// instead of crashing.
    init?(raw: String) {
        self.init(rawValue: raw)
    }
}

/// Catalog of seeded achievements. Each entry carries the persistent-field
/// values written into `Achievement` rows by `AchievementBootstrap`.
enum AchievementCatalog {
    struct Entry: Sendable {
        let key: String
        let titleKey: String
        let descriptionKey: String
        let condition: AchievementConditionType
        let conditionValue: Int
        let icon: String
    }

    static let entries: [Entry] = [
        .init(key: "first_lesson", titleKey: "achievement.first_lesson.title",
              descriptionKey: "achievement.first_lesson.description",
              condition: .lessonsCompleted, conditionValue: 1, icon: "flag.fill"),
        .init(key: "lessons_10", titleKey: "achievement.lessons_10.title",
              descriptionKey: "achievement.lessons_10.description",
              condition: .lessonsCompleted, conditionValue: 10, icon: "books.vertical.fill"),
        .init(key: "streak_7", titleKey: "achievement.streak_7.title",
              descriptionKey: "achievement.streak_7.description",
              condition: .streak, conditionValue: 7, icon: "flame.fill"),
        .init(key: "streak_30", titleKey: "achievement.streak_30.title",
              descriptionKey: "achievement.streak_30.description",
              condition: .streak, conditionValue: 30, icon: "flame.circle.fill"),
        .init(key: "xp_100", titleKey: "achievement.xp_100.title",
              descriptionKey: "achievement.xp_100.description",
              condition: .xp, conditionValue: 100, icon: "bolt.fill"),
        .init(key: "xp_1000", titleKey: "achievement.xp_1000.title",
              descriptionKey: "achievement.xp_1000.description",
              condition: .xp, conditionValue: 1000, icon: "star.circle.fill"),
        .init(key: "perfect_lesson", titleKey: "achievement.perfect_lesson.title",
              descriptionKey: "achievement.perfect_lesson.description",
              condition: .perfectLesson, conditionValue: 1, icon: "checkmark.seal.fill")
    ]
}
