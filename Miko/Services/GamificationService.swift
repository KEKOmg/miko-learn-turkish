import Foundation

/// Orchestrates the gamification business logic for a lesson completion:
/// UserProgress (XP + counters) → DailyGoal → Streak → Achievements.
///
/// Repositories own persistence; this service owns the *coordination* and
/// the idempotency rule: the same `completionID` is never awarded twice.
/// The caller (the lesson flow) generates a fresh `completionID` per lesson
/// run so legitimate replays still count, while accidental double-calls for
/// the same run are no-ops.
@MainActor
final class GamificationService {

    struct CompletionOutcome: Equatable {
        let xpAwarded: Int
        let gemsAwarded: Int
        let newlyEarnedAchievementKeys: [String]
        let wasDuplicate: Bool
    }

    /// XP awarded per correct answer. Single source of truth — the lesson
    /// flow reads this instead of keeping its own constant.
    static let xpPerCorrect = 10

    /// Gems awarded per completed lesson run. Flat per-lesson reward,
    /// independent of accuracy, mirroring Duolingo's soft-currency model.
    static let gemsPerLesson = 5

    private let gamificationRepository: GamificationRepository
    private let achievementRepository: AchievementRepository
    private var processedCompletionIDs: Set<UUID> = []

    init(
        gamificationRepository: GamificationRepository,
        achievementRepository: AchievementRepository
    ) {
        self.gamificationRepository = gamificationRepository
        self.achievementRepository = achievementRepository
    }

    /// Applies the full gamification pipeline for a finished lesson run.
    /// Idempotent per `completionID`: a second call with the same ID returns
    /// a duplicate outcome and performs no mutations.
    @discardableResult
    func applyLessonCompletion(
        user: UserProfile,
        correctCount: Int,
        answeredCount: Int,
        completionID: UUID,
        now: Date = Date()
    ) throws -> CompletionOutcome {
        guard !processedCompletionIDs.contains(completionID) else {
            return CompletionOutcome(
                xpAwarded: 0,
                gemsAwarded: 0,
                newlyEarnedAchievementKeys: [],
                wasDuplicate: true
            )
        }
        let xpAwarded = correctCount * Self.xpPerCorrect
        let gemsAwarded = Self.gemsPerLesson

        var newKeys: [String] = []
        try gamificationRepository.performTransaction {
            // 1. XP + counters (correct + answered totals).
            try gamificationRepository.applyProgress(
                for: user,
                xpToAdd: xpAwarded,
                correctAnswers: correctCount,
                exercisesAnswered: answeredCount
            )
            // totalLessonsCompleted is incremented separately so it stays a
            // clean +1 regardless of how many exercises were in the lesson.
            try gamificationRepository.incrementLessonsCompleted(for: user)

            // 1b. Gems: flat per-lesson reward.
            try gamificationRepository.addGems(gemsAwarded, for: user)

            // 2. Daily goal: reset on day rollover, then bank today's XP.
            try gamificationRepository.resetDailyGoalIfNeeded(for: user, now: now)
            try gamificationRepository.addDailyGoalXP(xpAwarded, for: user)

            // 3. Streak: advance (idempotent within the same calendar day).
            try gamificationRepository.advanceStreak(for: user, now: now)

            // 4. Achievements: evaluate and persist newly-earned entries.
            let perfectCount = try achievementRepository.fetchPerfectLessonCount(for: user)
            let state = AchievementEngine.State(
                xp: user.progress?.xp ?? 0,
                currentStreak: user.progress?.streak?.currentStreak ?? 0,
                totalLessonsCompleted: user.progress?.totalLessonsCompleted ?? 0,
                perfectLessonCount: perfectCount
            )
            let alreadyEarned = try achievementRepository.fetchEarnedKeys(for: user)
            newKeys = AchievementEngine.newlyEarnedKeys(
                state: state,
                alreadyEarned: alreadyEarned
            )
            _ = try achievementRepository.awardAchievements(
                keys: newKeys,
                for: user,
                now: now
            )
        }

        // Mark the completion only after the whole transaction succeeds so
        // a transient persistence error can be retried.
        processedCompletionIDs.insert(completionID)
        if !newKeys.isEmpty {
            Haptics.achievementEarned(enabled: user.settings?.hapticsEnabled ?? true)
        }

        return CompletionOutcome(
            xpAwarded: xpAwarded,
            gemsAwarded: gemsAwarded,
            newlyEarnedAchievementKeys: newKeys,
            wasDuplicate: false
        )
    }

    /// Convenience: reset the daily goal for the foreground/Home entry points.
    func resetDailyGoalIfNeeded(for user: UserProfile, now: Date = Date()) throws {
        try gamificationRepository.resetDailyGoalIfNeeded(for: user, now: now)
    }

    /// Awards XP for a practice session replay of a completed lesson. Does
    /// NOT increment lesson-completion counters, gems, streak, daily goal, or
    /// achievements — only adds XP to the user's cumulative total.
    struct PracticeOutcome: Equatable {
        let xpAwarded: Int
    }

    @discardableResult
    func applyPracticeCompletion(
        user: UserProfile,
        correctCount: Int
    ) throws -> PracticeOutcome {
        let xpAwarded = correctCount * Self.xpPerCorrect
        try gamificationRepository.addPracticeXP(xpAwarded, for: user)
        return PracticeOutcome(xpAwarded: xpAwarded)
    }
}
