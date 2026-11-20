import Foundation

/// Immutable, SwiftData-free snapshot of the user's profile state for the
/// Profile screen. Carries stats plus the earned/locked achievement rows.
struct ProfileSnapshot: Equatable {

    struct Stat: Equatable, Sendable {
        let xp: Int
        let streakDays: Int
        let heartsRemaining: Int
        let heartsTotal: Int
        let lessonsCompleted: Int
    }

    struct AchievementRow: Equatable, Identifiable, Sendable {
        enum Kind: Equatable, Sendable {
            case earned(date: Date)
            case locked(progress: Double)
        }

        let id: String
        let key: String
        let titleKey: String
        let descriptionKey: String
        let icon: String
        let kind: Kind
    }

    let stat: Stat
    let achievements: [AchievementRow]

    /// Number of earned achievements.
    var earnedCount: Int {
        achievements.lazy.filter {
            if case .earned = $0.kind { return true }
            return false
        }.count
    }
}
