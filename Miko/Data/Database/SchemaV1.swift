import Foundation
import SwiftData

/// Frozen snapshot of the v1 production SwiftData schema.
///
/// This enumerates the exact set of `@Model` types as they exist today,
/// including `UserProgress.gems`. Once shipped, these model definitions are
/// effectively immutable: any future property or relationship change requires
/// a new `SchemaV2` plus a `MigrationStage` in `DatabaseMigrationPlan` —
/// never an in-place edit of a v1 model.
enum SchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Language.self,
            Course.self,
            Level.self,
            Unit.self,
            Lesson.self,
            Exercise.self,
            VocabularyItem.self,
            GrammarTopic.self,
            UserProfile.self,
            UserProgress.self,
            LessonProgress.self,
            ExerciseProgress.self,
            Achievement.self,
            UserAchievement.self,
            DailyGoal.self,
            Streak.self,
            UserSettings.self,
            Hearts.self
        ]
    }
}
