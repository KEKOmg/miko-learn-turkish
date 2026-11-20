import Foundation
import SwiftData
import Testing
@testable import Miko

/// Tests for `GamificationService` orchestration: XP award, counter
/// increments, daily-goal reset + add, streak advancement, achievement
/// awarding, and idempotency against duplicate completion IDs.
@MainActor
struct GamificationServiceTests {

    // MARK: - Fixtures

    private struct Fixture {
        let context: ModelContext
        let user: UserProfile
        let service: GamificationService
        let gamificationRepo: GamificationRepository
        let achievementRepo: AchievementRepository
    }

    private func makeFixture() throws -> Fixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        let progress = UserProgress()
        progress.user = user
        context.insert(progress)
        let streak = Streak(user: user)
        progress.streak = streak
        context.insert(streak)
        let goal = DailyGoal(xpTarget: 50, xpEarnedToday: 0, user: user)
        progress.dailyGoal = goal
        context.insert(goal)
        try context.save()

        let gamificationRepo = GamificationRepository(context: context)
        let achievementRepo = AchievementRepository(context: context)
        let service = GamificationService(
            gamificationRepository: gamificationRepo,
            achievementRepository: achievementRepo
        )
        return Fixture(
            context: context, user: user, service: service,
            gamificationRepo: gamificationRepo, achievementRepo: achievementRepo
        )
    }

    // MARK: - XP + counters

    @Test func xpIncreasesByCorrectCountTimesTen() throws {
        let f = try makeFixture()
        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 3, answeredCount: 4,
            completionID: UUID()
        )
        #expect(f.user.progress?.xp == 30)
    }

    @Test func countersIncrement() throws {
        let f = try makeFixture()
        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 2, answeredCount: 5,
            completionID: UUID()
        )
        #expect(f.user.progress?.totalCorrectAnswers == 2)
        #expect(f.user.progress?.totalExercisesAnswered == 5)
        #expect(f.user.progress?.totalLessonsCompleted == 1)
    }

    @Test func dailyGoalUpdatesWithXP() throws {
        let f = try makeFixture()
        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 4, answeredCount: 4,
            completionID: UUID()
        )
        #expect(f.user.progress?.dailyGoal?.xpEarnedToday == 40)
    }

    // MARK: - Gems

    @Test func gemsIncreaseByFivePerLesson() throws {
        let f = try makeFixture()
        let outcome = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 2, answeredCount: 3,
            completionID: UUID()
        )
        #expect(outcome.gemsAwarded == GamificationService.gemsPerLesson)
        #expect(f.user.progress?.gems == 5)
    }

    @Test func gemsAwardedEvenWithZeroCorrect() throws {
        let f = try makeFixture()
        // A completed lesson still awards gems regardless of accuracy.
        let outcome = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 0, answeredCount: 4,
            completionID: UUID()
        )
        #expect(outcome.gemsAwarded == GamificationService.gemsPerLesson)
        #expect(f.user.progress?.gems == 5)
    }

    @Test func duplicateCompletionDoesNotDoubleAwardGems() throws {
        let f = try makeFixture()
        let id = UUID()
        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: id
        )
        let second = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: id
        )
        #expect(second.wasDuplicate == true)
        #expect(second.gemsAwarded == 0)
        #expect(f.user.progress?.gems == GamificationService.gemsPerLesson)
    }

    @Test func distinctCompletionsAccumulateGems() throws {
        let f = try makeFixture()
        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: UUID()
        )
        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: UUID()
        )
        #expect(f.user.progress?.gems == GamificationService.gemsPerLesson * 2)
    }

    @Test func gemsStartAtZeroForNewProgress() throws {
        let f = try makeFixture()
        // Fixture creates a fresh UserProgress; gems must default to 0.
        #expect(f.user.progress?.gems == 0)
    }

    // MARK: - Idempotency

    @Test func duplicateCompletionDoesNotDoubleCount() throws {
        let f = try makeFixture()
        let id = UUID()
        let first = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 3, answeredCount: 4, completionID: id
        )
        let second = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 3, answeredCount: 4, completionID: id
        )

        #expect(first.wasDuplicate == false)
        #expect(second.wasDuplicate == true)
        #expect(second.xpAwarded == 0)
        #expect(f.user.progress?.xp == 30)
        #expect(f.user.progress?.totalLessonsCompleted == 1)
        #expect(f.user.progress?.dailyGoal?.xpEarnedToday == 30)
    }

    @Test func distinctCompletionIDsBothCount() throws {
        let f = try makeFixture()
        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 2, answeredCount: 2, completionID: UUID()
        )
        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: UUID()
        )
        // Two distinct lesson runs → XP accumulates.
        #expect(f.user.progress?.xp == 30)
        #expect(f.user.progress?.totalLessonsCompleted == 2)
    }

    // MARK: - Daily goal reset

    @Test func dailyGoalResetsOnNewDay() throws {
        let f = try makeFixture()
        // Earn some XP yesterday.
        let yesterday = CalendarDay.current.date(byAdding: .day, value: -1, to: Date())!
        f.user.progress?.dailyGoal?.date = yesterday
        f.user.progress?.dailyGoal?.xpEarnedToday = 40
        try f.context.save()

        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 2, answeredCount: 2,
            completionID: UUID()
        )
        #expect(f.user.progress?.dailyGoal?.xpEarnedToday == 20)
        #expect(CalendarDay.isSameDay(f.user.progress!.dailyGoal!.date, Date()))
    }

    @Test func dailyGoalSameDayAccumulates() throws {
        let f = try makeFixture()
        f.user.progress?.dailyGoal?.xpEarnedToday = 20
        try f.context.save()

        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1,
            completionID: UUID()
        )
        #expect(f.user.progress?.dailyGoal?.xpEarnedToday == 30)
    }

    // MARK: - Streak

    @Test func streakFirstDaySetsToOne() throws {
        let f = try makeFixture()
        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: UUID()
        )
        #expect(f.user.progress?.streak?.currentStreak == 1)
        #expect(f.user.progress?.streak?.longestStreak == 1)
    }

    @Test func streakConsecutiveDayIncrements() throws {
        let f = try makeFixture()
        let yesterday = CalendarDay.current.date(byAdding: .day, value: -1, to: Date())!
        f.user.progress?.streak?.currentStreak = 3
        f.user.progress?.streak?.longestStreak = 3
        f.user.progress?.streak?.lastActiveDate = yesterday
        try f.context.save()

        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: UUID()
        )
        #expect(f.user.progress?.streak?.currentStreak == 4)
        #expect(f.user.progress?.streak?.longestStreak == 4)
    }

    @Test func streakSameDayUnchanged() throws {
        let f = try makeFixture()
        f.user.progress?.streak?.currentStreak = 5
        f.user.progress?.streak?.longestStreak = 5
        f.user.progress?.streak?.lastActiveDate = Date()
        try f.context.save()

        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: UUID()
        )
        #expect(f.user.progress?.streak?.currentStreak == 5)
    }

    @Test func streakMissedDayResetsToOne() throws {
        let f = try makeFixture()
        let threeDaysAgo = CalendarDay.current.date(byAdding: .day, value: -3, to: Date())!
        f.user.progress?.streak?.currentStreak = 10
        f.user.progress?.streak?.longestStreak = 10
        f.user.progress?.streak?.lastActiveDate = threeDaysAgo
        try f.context.save()

        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: UUID()
        )
        #expect(f.user.progress?.streak?.currentStreak == 1)
        #expect(f.user.progress?.streak?.longestStreak == 10)
    }

    // MARK: - Achievements awarded via service

    @Test func firstLessonAchievementAwardedOnCompletion() throws {
        let f = try makeFixture()
        try AchievementBootstrap.bootstrapIfNeeded(context: f.context)
        let outcome = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: UUID()
        )
        #expect(outcome.newlyEarnedAchievementKeys.contains("first_lesson"))
        let earned = try f.achievementRepo.fetchEarnedKeys(for: f.user)
        #expect(earned.contains("first_lesson"))
    }

    @Test func xp100AchievementAwardedWhenXPReachesThreshold() throws {
        let f = try makeFixture()
        try AchievementBootstrap.bootstrapIfNeeded(context: f.context)
        // 10 correct × 10 XP = 100 XP.
        let outcome = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 10, answeredCount: 10, completionID: UUID()
        )
        #expect(outcome.newlyEarnedAchievementKeys.contains("xp_100"))
        #expect(f.user.progress?.xp == 100)
    }

    @Test func achievementsNotDoubleAwarded() throws {
        let f = try makeFixture()
        try AchievementBootstrap.bootstrapIfNeeded(context: f.context)
        _ = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: UUID()
        )
        let secondOutcome = try f.service.applyLessonCompletion(
            user: f.user, correctCount: 1, answeredCount: 1, completionID: UUID()
        )
        // first_lesson already earned — not in the newly-earned list.
        #expect(!secondOutcome.newlyEarnedAchievementKeys.contains("first_lesson"))
        let earned = try f.achievementRepo.fetchEarnedKeys(for: f.user)
        #expect(earned.filter { $0 == "first_lesson" }.count == 1)
    }
}
