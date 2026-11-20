import Foundation
import SwiftData

/// Owns achievement persistence: reading the catalog, reading/writing
/// `UserAchievement` awards, and deriving the perfect-lesson count from
/// `LessonProgress`. Awarding is idempotent — calling it for a key the user
/// already earned is a no-op.
struct AchievementRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Catalog

    /// Returns all seeded `Achievement` rows sorted by `key` for stable
    /// display order.
    func fetchCatalog() throws -> [Achievement] {
        try context.fetch(FetchDescriptor<Achievement>())
            .sorted { $0.key < $1.key }
    }

    // MARK: - Earned state

    /// Returns the `UserAchievement` rows for the given user, sorted by
    /// `earnedAt` ascending.
    func fetchEarnedAchievements(for user: UserProfile) throws -> [UserAchievement] {
        let userID = user.id
        let predicate = #Predicate<UserAchievement> { $0.user?.id == userID }
        return try context.fetch(FetchDescriptor<UserAchievement>(predicate: predicate))
            .sorted { $0.earnedAt < $1.earnedAt }
    }

    /// Returns the set of achievement keys the user has already earned.
    func fetchEarnedKeys(for user: UserProfile) throws -> Set<String> {
        let earned = try fetchEarnedAchievements(for: user)
        return Set(earned.compactMap { $0.achievement?.key })
    }

    // MARK: - Awarding

    /// Awards the achievements identified by `keys` for the given user.
    /// Idempotent: keys the user already owns are skipped. Returns the
    /// newly-awarded `UserAchievement` rows (empty when nothing changed).
    @discardableResult
    func awardAchievements(
        keys: [String],
        for user: UserProfile,
        now: Date = Date()
    ) throws -> [UserAchievement] {
        guard !keys.isEmpty else { return [] }
        let alreadyEarned = try fetchEarnedKeys(for: user)
        let toAward = Set(keys).subtracting(alreadyEarned)
        guard !toAward.isEmpty else { return [] }

        let catalog = try fetchCatalog()
        var catalogByKey: [String: Achievement] = [:]
        for achievement in catalog { catalogByKey[achievement.key] = achievement }

        var awarded: [UserAchievement] = []
        for key in toAward {
            guard let achievement = catalogByKey[key] else { continue }
            let userAchievement = UserAchievement(earnedAt: now, progress: 0, user: user, achievement: achievement)
            context.insert(userAchievement)
            awarded.append(userAchievement)
        }
        if !awarded.isEmpty { try context.save() }
        return awarded
    }

    // MARK: - Perfect lessons

    /// Counts completed lessons with `bestAccuracy == 1.0` for the user.
    /// Derived from `LessonProgress` so no denormalized counter is needed.
    func fetchPerfectLessonCount(for user: UserProfile) throws -> Int {
        let userID = user.id
        let predicate = #Predicate<LessonProgress> {
            $0.statusRaw == "completed" && $0.bestAccuracy == 1.0
        }
        return try context.fetch(FetchDescriptor<LessonProgress>(predicate: predicate))
            .filter { $0.user?.id == userID }
            .count
    }
}
