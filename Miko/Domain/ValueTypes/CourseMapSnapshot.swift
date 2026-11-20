import Foundation

/// Immutable, SwiftData-free snapshots of the course structure and the
/// user's progress through it. Views and view models consume these so that
/// no SwiftData model objects leak into SwiftUI rendering code, and so the
/// navigation logic is unit-testable without a UI.

/// Per-lesson visual state on the course map and the Home CTA.
enum LessonState: Equatable, Hashable {
    /// Not yet available — a previous lesson must be completed first.
    case locked
    /// Available to play but not yet finished.
    case unlocked
    /// Finished at least once. Carries the best-accuracy-derived star count
    /// (1...3) and the best accuracy (0...1) for display.
    case completed(stars: Int, accuracy: Double)
}

/// A single lesson node in the map, with its computed state.
struct LessonNode: Equatable, Identifiable, Hashable {
    let id: UUID
    let key: String
    let titleKey: String
    let orderIndex: Int
    let state: LessonState

    /// True when the user can launch this lesson right now.
    var isPlayable: Bool {
        switch state {
        case .locked: return false
        case .unlocked, .completed: return true
        }
    }
}

/// A unit section grouping its lessons.
struct UnitSection: Equatable, Identifiable, Hashable {
    let id: UUID
    let key: String
    let titleKey: String
    let summaryKey: String
    let theme: String
    let orderIndex: Int
    let lessons: [LessonNode]

    /// Number of completed lessons in this unit.
    var completedCount: Int {
        lessons.lazy.filter {
            if case .completed = $0.state { return true }
            return false
        }.count
    }
}

/// A level section grouping its units.
struct LevelSection: Equatable, Identifiable, Hashable {
    let id: UUID
    let key: String
    let cefrRaw: String
    let orderIndex: Int
    let units: [UnitSection]

    /// True once every lesson in the level has been completed.
    var isCompleted: Bool {
        let lessons = units.flatMap(\.lessons)
        guard !lessons.isEmpty else { return false }
        return lessons.allSatisfy {
            if case .completed = $0.state { return true }
            return false
        }
    }

    /// Whether the level has at least one lesson the learner can enter.
    /// Locked levels remain visible in the level picker so learners can
    /// preview what comes next.
    var isAvailable: Bool {
        units.lazy.flatMap(\.lessons).contains(where: \.isPlayable)
    }
}

/// Full ordered snapshot of a course used by the Course Map screen.
struct CourseMapSnapshot: Equatable {
    let courseKey: String
    let levels: [LevelSection]

    /// Flattened lessons in their global play order (level → unit → lesson).
    var allLessons: [LessonNode] {
        levels.flatMap { $0.units.flatMap(\.lessons) }
    }

    /// Level the map should present initially. This is the first level with
    /// an unlocked, unfinished lesson; once the whole course is complete the
    /// final level remains selected for practice.
    var suggestedLevelKey: String? {
        for level in levels {
            let hasUnlockedLesson = level.units.lazy
                .flatMap(\.lessons)
                .contains { $0.state == .unlocked }
            if hasUnlockedLesson { return level.key }
        }
        return levels.last?.key
    }
}

/// Home screen stats. Hearts are a placeholder until the gamification
/// service arrives in Phase 5; the values mirror the lesson flow's current
/// placeholder heart economy.
struct UserStatsSnapshot: Equatable {
    let xp: Int
    let streakDays: Int
    let heartsTotal: Int
    let heartsRemaining: Int
    let dailyGoalXP: Int
    let dailyGoalEarned: Int

    /// Daily goal completion ratio (0...1).
    var dailyGoalProgress: Double {
        guard dailyGoalXP > 0 else { return 0 }
        return min(Double(dailyGoalEarned) / Double(dailyGoalXP), 1)
    }

    var isDailyGoalReached: Bool {
        dailyGoalEarned >= dailyGoalXP && dailyGoalXP > 0
    }
}

/// Lightweight next-lesson info for the Home CTA.
struct NextLessonSnapshot: Equatable {
    let id: UUID
    let titleKey: String
    let unitTitleKey: String
}
