import Foundation
import SwiftData
import Testing
@testable import Miko

/// Tests for `ProfileViewModel`: snapshot construction, stat aggregation,
/// and earned/locked achievement classification.
@MainActor
struct ProfileViewModelTests {

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let user: UserProfile
        let viewModel: ProfileViewModel
        let achievementRepo: AchievementRepository
    }

    private func makeFixture(
        xp: Int = 0,
        streak: Int = 0,
        lessonsCompleted: Int = 0,
        hearts: Int = 5
    ) throws -> Fixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        let progress = UserProgress()
        progress.xp = xp
        progress.totalLessonsCompleted = lessonsCompleted
        progress.user = user
        context.insert(progress)
        let streakModel = Streak(currentStreak: streak, longestStreak: streak, user: user)
        progress.streak = streakModel
        context.insert(streakModel)
        let goal = DailyGoal(xpTarget: 50, xpEarnedToday: 0, user: user)
        progress.dailyGoal = goal
        context.insert(goal)
        let heartsModel = Hearts(currentHearts: hearts, maxHearts: 5, user: user)
        context.insert(heartsModel)
        try AchievementBootstrap.bootstrapIfNeeded(context: context)
        try context.save()

        let lessonRepo = LessonProgressRepository(context: context)
        let achievementRepo = AchievementRepository(context: context)
        let heartsRepo = HeartsRepository(context: context)
        let viewModel = ProfileViewModel(
            lessonProgressRepository: lessonRepo,
            achievementRepository: achievementRepo,
            heartsRepository: heartsRepo
        )
        return Fixture(
            container: container,
            context: context,
            user: user,
            viewModel: viewModel,
            achievementRepo: achievementRepo
        )
    }

    @Test func loadProducesSnapshotWithStats() throws {
        let f = try makeFixture(xp: 120, streak: 4, lessonsCompleted: 3, hearts: 3)
        f.viewModel.load()

        #expect(f.viewModel.phase == .ready)
        let stat = f.viewModel.snapshot?.stat
        #expect(stat?.xp == 120)
        #expect(stat?.streakDays == 4)
        #expect(stat?.lessonsCompleted == 3)
        #expect(stat?.heartsRemaining == 3)
        #expect(stat?.heartsTotal == 5)
    }

    @Test func loadProducesAllAchievementRows() throws {
        let f = try makeFixture()
        f.viewModel.load()

        let rows = f.viewModel.snapshot?.achievements ?? []
        #expect(rows.count == AchievementCatalog.entries.count)
    }

    @Test func earnedAchievementHasEarnedKind() throws {
        let f = try makeFixture()
        _ = try f.achievementRepo.awardAchievements(keys: ["first_lesson"], for: f.user)
        f.viewModel.load()

        let firstLesson = f.viewModel.snapshot?.achievements.first { $0.key == "first_lesson" }
        if case .earned = firstLesson?.kind {
            // ok
        } else {
            Issue.record("Expected first_lesson to be earned")
        }
    }

    @Test func unearnedAchievementIsLockedWithProgress() throws {
        let f = try makeFixture(xp: 30)
        f.viewModel.load()

        let xp100 = f.viewModel.snapshot?.achievements.first { $0.key == "xp_100" }
        guard case .locked(let p) = xp100?.kind else {
            Issue.record("Expected xp_100 to be locked")
            return
        }
        #expect(abs(p - 0.3) < 0.0001)
    }

    @Test func earnedCountReflectsAwarded() throws {
        let f = try makeFixture()
        _ = try f.achievementRepo.awardAchievements(keys: ["first_lesson", "xp_100"], for: f.user)
        f.viewModel.load()

        #expect(f.viewModel.snapshot?.earnedCount == 2)
    }

    @Test func loadIsSafeWhenNoProfile() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let lessonRepo = LessonProgressRepository(context: context)
        let achievementRepo = AchievementRepository(context: context)
        let heartsRepo = HeartsRepository(context: context)
        let viewModel = ProfileViewModel(
            lessonProgressRepository: lessonRepo,
            achievementRepository: achievementRepo,
            heartsRepository: heartsRepo
        )
        viewModel.load()
        // No crash; phase reports failure.
        if case .failed = viewModel.phase {
            // ok
        } else {
            Issue.record("Expected failed phase with no profile")
        }
    }

    @Test func profileSnapshotEquality() {
        let stat = ProfileSnapshot.Stat(xp: 10, streakDays: 1, heartsRemaining: 5, heartsTotal: 5, lessonsCompleted: 1)
        let row = ProfileSnapshot.AchievementRow(
            id: "x", key: "k", titleKey: "t", descriptionKey: "d",
            icon: "i", kind: .earned(date: Date(timeIntervalSince1970: 0))
        )
        let a = ProfileSnapshot(stat: stat, achievements: [row])
        let b = ProfileSnapshot(stat: stat, achievements: [row])
        #expect(a == b)
        #expect(a.earnedCount == 1)
    }

    @Test func selectedDailyGoalPersists() throws {
        let fixture = try makeFixture()
        let goal = try #require(fixture.user.progress?.dailyGoal)

        goal.xpTarget = 200
        try fixture.context.save()

        let verificationContext = ModelContext(fixture.container)
        let persistedGoal = try #require(
            verificationContext.fetch(FetchDescriptor<DailyGoal>()).first
        )
        #expect(persistedGoal.xpTarget == 200)
    }
}
