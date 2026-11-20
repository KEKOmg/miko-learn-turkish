import Foundation

/// Pure, SwiftData-free evaluation of achievement conditions. The engine
/// takes an immutable snapshot of the user's gamification state and reports
/// which catalog entries are earned and (where supported) their progress.
/// Awarding rows in SwiftData is the repository's job — this type owns only
/// the business rule.
struct AchievementEngine: Sendable {
    /// Immutable snapshot of the gamification state the engine evaluates
    /// against. Carries only the values that map to condition types.
    struct State: Sendable, Equatable {
        let xp: Int
        let currentStreak: Int
        let totalLessonsCompleted: Int
        /// Count of lesson runs with accuracy == 1.0 (perfect). Tracking is
        /// additive across runs; the repository updates it on completion.
        let perfectLessonCount: Int
    }

    /// Result of evaluating a single catalog entry against a state.
    enum Evaluation: Sendable, Equatable {
        /// Already earned; no further work needed.
        case earned
        /// Not yet earned; carries progress 0...1 toward the threshold.
        case locked(progress: Double)
    }

    /// Returns `true` when the entry's threshold is met.
    static func isEarned(_ entry: AchievementCatalog.Entry, state: State) -> Bool {
        value(for: entry.condition, state: state) >= entry.conditionValue
    }

    /// Returns a progress ratio 0...1 for the entry.
    static func progress(_ entry: AchievementCatalog.Entry, state: State) -> Double {
        let value = value(for: entry.condition, state: state)
        guard entry.conditionValue > 0 else { return 1 }
        return min(Double(value) / Double(entry.conditionValue), 1)
    }

    /// Returns the evaluation for every catalog entry, keyed by `key`.
    static func evaluateAll(state: State) -> [String: Evaluation] {
        var result: [String: Evaluation] = [:]
        for entry in AchievementCatalog.entries {
            if isEarned(entry, state: state) {
                result[entry.key] = .earned
            } else {
                result[entry.key] = .locked(progress: progress(entry, state: state))
            }
        }
        return result
    }

    /// Returns only the keys that are newly earned given the state.
    static func newlyEarnedKeys(state: State, alreadyEarned: Set<String>) -> [String] {
        AchievementCatalog.entries
            .filter { isEarned($0, state: state) }
            .map(\.key)
            .filter { !alreadyEarned.contains($0) }
    }

    // MARK: - Helpers

    private static func value(
        for condition: AchievementConditionType,
        state: State
    ) -> Int {
        switch condition {
        case .lessonsCompleted: return state.totalLessonsCompleted
        case .streak: return state.currentStreak
        case .xp: return state.xp
        case .perfectLesson: return state.perfectLessonCount
        }
    }
}
