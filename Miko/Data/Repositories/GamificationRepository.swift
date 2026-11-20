import Foundation
import SwiftData

/// Owns `UserProgress`, `Streak`, and `DailyGoal` mutations: XP and counter
/// increments, daily-goal reset, and streak advancement. The orchestration
/// of *when* to call these is `GamificationService`'s job; this repository
/// owns the persistence mechanics and the invariants (no negative counters,
/// idempotent streak update per day, etc.).
struct GamificationRepository {
    private let context: ModelContext
    private let profileID: UUID?

    init(context: ModelContext, profileID: UUID? = nil) {
        self.context = context
        self.profileID = profileID
    }

    /// Runs a coordinated mutation in the repository's model transaction.
    /// Collaborating repositories used by the caller must share this same
    /// `ModelContext` (as they do in `AppContainer`).
    func performTransaction(_ block: () throws -> Void) throws {
        try context.transaction(block: block)
    }

    // MARK: - Fetching

    func fetchPrimaryUserProfile() throws -> UserProfile? {
        if let profileID {
            let predicate = #Predicate<UserProfile> { $0.id == profileID }
            var descriptor = FetchDescriptor<UserProfile>(predicate: predicate)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
        }
        // Compatibility for single-profile callers/tests only. An omitted
        // owner must never pick an arbitrary account in a multi-user store.
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 2
        let profiles = try context.fetch(descriptor)
        return profiles.count == 1 ? profiles[0] : nil
    }

    // MARK: - XP + counters

    /// Applies the persistent XP and counter increments for a lesson run.
    /// Each call adds to the user's cumulative totals — this represents one
    /// answered lesson, not a deduplicated completion. Idempotency against
    /// double-counting the same lesson completion is handled at the
    /// `GamificationService` level (which guards on `LessonProgress.id`).
    @discardableResult
    func applyProgress(
        for user: UserProfile,
        xpToAdd: Int,
        correctAnswers: Int,
        exercisesAnswered: Int
    ) throws -> UserProgress {
        guard let progress = user.progress else {
            let progress = UserProgress()
            progress.user = user
            context.insert(progress)
            progress.xp = 0
            progress.totalLessonsCompleted = 0
            progress.totalCorrectAnswers = 0
            progress.totalExercisesAnswered = 0
            return try applyProgress(
                for: user, xpToAdd: xpToAdd,
                correctAnswers: correctAnswers,
                exercisesAnswered: exercisesAnswered
            )
        }
        progress.xp += max(0, xpToAdd)
        progress.totalCorrectAnswers += max(0, correctAnswers)
        progress.totalExercisesAnswered += max(0, exercisesAnswered)
        try context.save()
        return progress
    }

    /// Increments `totalLessonsCompleted` by 1 for the user.
    @discardableResult
    func incrementLessonsCompleted(for user: UserProfile) throws -> UserProgress {
        guard let progress = user.progress else {
            let progress = UserProgress()
            progress.user = user
            context.insert(progress)
            try context.save()
            return try incrementLessonsCompleted(for: user)
        }
        progress.totalLessonsCompleted += 1
        try context.save()
        return progress
    }

    // MARK: - Gems

    /// Adds gems to the user's balance. Never goes below 0. Lazily creates
    /// the `UserProgress` row if missing (mirrors `applyProgress`).
    @discardableResult
    func addGems(_ amount: Int, for user: UserProfile) throws -> UserProgress {
        guard let progress = user.progress else {
            let progress = UserProgress()
            progress.user = user
            context.insert(progress)
            return try addGems(amount, for: user)
        }
        progress.gems += max(0, amount)
        try context.save()
        return progress
    }

    /// Adds XP from a practice session. Does NOT increment lesson-completion
    /// counters, correct/answered totals, gems, streak, or daily goal. Used
    /// only for practice replays of completed lessons.
    @discardableResult
    func addPracticeXP(_ xp: Int, for user: UserProfile) throws -> UserProgress {
        guard let progress = user.progress else {
            let progress = UserProgress()
            progress.user = user
            context.insert(progress)
            return try addPracticeXP(xp, for: user)
        }
        progress.xp += max(0, xp)
        try context.save()
        return progress
    }

    /// Spends gems from the user's balance. Returns `true` and debits the
    /// amount when the balance is sufficient; returns `false` and performs
    /// no mutation when the balance is insufficient or no `UserProgress`
    /// exists. Never allows gems to become negative.
    @discardableResult
    func spendGems(_ amount: Int, for user: UserProfile) throws -> Bool {
        guard let progress = user.progress, amount > 0 else { return false }
        guard progress.gems >= amount else { return false }
        progress.gems -= amount
        try context.save()
        return true
    }

    /// Atomically spends gems and refills the user's hearts.
    ///
    /// Keeping both mutations in one `ModelContext` transaction prevents a
    /// failed heart refill from leaving the user with gems already deducted.
    /// Returns `false` without mutating state when the purchase is invalid.
    @discardableResult
    func purchaseHeartRefill(
        cost: Int,
        for user: UserProfile,
        now: Date = Date()
    ) throws -> Bool {
        guard cost > 0, let progress = user.progress else { return false }

        let userID = user.id
        let predicate = #Predicate<Hearts> { $0.user?.id == userID }
        var descriptor = FetchDescriptor<Hearts>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let hearts = try context.fetch(descriptor).first,
              hearts.currentHearts < hearts.maxHearts,
              progress.gems >= cost else {
            return false
        }

        try context.transaction {
            progress.gems -= cost
            hearts.currentHearts = hearts.maxHearts
            hearts.lastRegeneratedAt = now
            try context.save()
        }
        return true
    }

    // MARK: - Daily goal

    /// Resets `xpEarnedToday` to 0 and updates `date` to today when the
    /// stored date is not the local current day. No-op on same day. Never
    /// changes `xpTarget`.
    @discardableResult
    func resetDailyGoalIfNeeded(for user: UserProfile, now: Date = Date()) throws -> DailyGoal? {
        guard let goal = user.progress?.dailyGoal else { return nil }
        if !CalendarDay.isSameDay(goal.date, now) {
            goal.xpEarnedToday = 0
            goal.date = now
            try context.save()
        }
        return goal
    }

    /// Adds XP to today's daily-goal tally. The caller is responsible for
    /// resetting first when crossing a day boundary.
    @discardableResult
    func addDailyGoalXP(_ xp: Int, for user: UserProfile) throws -> DailyGoal? {
        guard let goal = user.progress?.dailyGoal else { return nil }
        goal.xpEarnedToday += max(0, xp)
        try context.save()
        return goal
    }

    // MARK: - Streak

    /// Advances the streak for the given user based on `lastActiveDate`.
    /// Rules:
    /// - No previous activity → streak = 1.
    /// - Last active is today → unchanged (idempotent per day).
    /// - Last active is yesterday → +1.
    /// - Older (or nil) → reset to 1.
    /// Updates `longestStreak` when the new current streak exceeds it.
    /// Sets `lastActiveDate` to `now`.
    @discardableResult
    func advanceStreak(for user: UserProfile, now: Date = Date()) throws -> Streak? {
        guard let streak = user.progress?.streak else { return nil }
        let lastActive = streak.lastActiveDate

        let newCurrent: Int
        if let lastActive, CalendarDay.isSameDay(lastActive, now) {
            // Already updated today — no change.
            return streak
        } else if let lastActive, CalendarDay.isNextDay(lastActive, now) {
            newCurrent = streak.currentStreak + 1
        } else {
            newCurrent = 1
        }

        streak.currentStreak = newCurrent
        if newCurrent > streak.longestStreak {
            streak.longestStreak = newCurrent
        }
        streak.lastActiveDate = now
        try context.save()
        return streak
    }
}
