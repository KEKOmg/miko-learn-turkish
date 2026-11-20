import Foundation
import SwiftData
import Testing
@testable import Miko

/// Tests for practice mode: replaying a completed lesson without consuming
/// hearts and without triggering normal lesson-completion gamification.
///
/// Covers:
/// - starting practice with 0 hearts;
/// - incorrect answers do not decrement hearts;
/// - practice never enters depleted phase;
/// - practice awards XP but not gems, streak, lesson counter, or achievements;
/// - practice updates attempts and bestAccuracy;
/// - normal lesson behavior is unchanged (hearts decrement, full gamification);
/// - CourseMapViewModel selects the correct session mode for completed vs
///   unlocked vs locked lessons.
@MainActor
struct PracticeModeTests {

    // MARK: - Fixtures

    private struct Fixture {
        let context: ModelContext
        let repository: LessonProgressRepository
        let heartsRepository: HeartsRepository
        let gamificationRepository: GamificationRepository
        let achievementRepository: AchievementRepository
        let gamificationService: GamificationService
        let user: UserProfile
        let lesson: Lesson
    }

    private func makeFixture(
        initialHearts: Int = 5,
        gems: Int = 0
    ) throws -> Fixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)

        let progress = UserProgress()
        progress.gems = gems
        progress.user = user
        context.insert(progress)

        let streak = Streak(user: user)
        progress.streak = streak
        context.insert(streak)

        let goal = DailyGoal(xpTarget: 50, xpEarnedToday: 0, user: user)
        progress.dailyGoal = goal
        context.insert(goal)

        let hearts = Hearts(currentHearts: initialHearts, maxHearts: 5, user: user)
        context.insert(hearts)

        let lesson = Lesson(key: "a1.u1.l1", orderIndex: 0, titleKey: "lesson.a1.u1.l1.title", kind: .skill)
        context.insert(lesson)

        for index in 0..<3 {
            let exercise = Exercise(
                key: "e\(index)",
                orderIndex: index,
                type: .translateWord,
                promptText: "Prompt \(index)",
                payloadData: nil,
                correctAnswerText: "Merhaba",
                acceptedAnswers: ["merhaba"],
                lesson: lesson
            )
            context.insert(exercise)
        }
        try context.save()

        let gamificationRepo = GamificationRepository(context: context)
        let achievementRepo = AchievementRepository(context: context)
        return Fixture(
            context: context,
            repository: LessonProgressRepository(context: context),
            heartsRepository: HeartsRepository(context: context),
            gamificationRepository: gamificationRepo,
            achievementRepository: achievementRepo,
            gamificationService: GamificationService(
                gamificationRepository: gamificationRepo,
                achievementRepository: achievementRepo
            ),
            user: user,
            lesson: lesson
        )
    }

    private func makeViewModel(_ fixture: Fixture, mode: LessonSessionMode) -> LessonFlowViewModel {
        LessonFlowViewModel(
            repository: fixture.repository,
            heartsRepository: fixture.heartsRepository,
            gamificationService: fixture.gamificationService,
            duplicateSubmissionWindow: 0
        )
    }

    private func completeAll(_ viewModel: LessonFlowViewModel, results: [ExerciseResult]) {
        for result in results {
            viewModel.submitAndAdvance(result)
        }
    }

    // MARK: - Hearts: practice with 0 hearts

    @Test func practiceCanStartWithZeroHearts() throws {
        let f = try makeFixture(initialHearts: 0)
        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)

        #expect(vm.phase == .playing)
        #expect(vm.remainingHearts == 0)
        #expect(vm.sessionMode == .practice)
    }

    @Test func normalLessonCannotStartWithZeroHearts() throws {
        let f = try makeFixture(initialHearts: 0)
        let vm = makeViewModel(f, mode: .normal)
        vm.load(lessonID: f.lesson.id, mode: .normal)

        guard case .failed = vm.phase else {
            Issue.record("Expected failed phase when hearts == 0 in normal mode")
            return
        }
    }

    // MARK: - Hearts: incorrect answers do not decrement in practice

    @Test func incorrectAnswerDoesNotDecrementHeartsInPractice() throws {
        let f = try makeFixture(initialHearts: 5)
        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)

        vm.submitAndAdvance(.incorrect(canonicalAnswer: "Merhaba"))

        #expect(vm.remainingHearts == 5)
        #expect(try f.heartsRepository.fetchHearts(for: f.user)?.currentHearts == 5)
    }

    @Test func multipleIncorrectAnswersDoNotDecrementHeartsInPractice() throws {
        let f = try makeFixture(initialHearts: 3)
        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)

        vm.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        vm.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        vm.submitAndAdvance(.incorrect(canonicalAnswer: "a"))

        #expect(vm.remainingHearts == 3)
        #expect(try f.heartsRepository.fetchHearts(for: f.user)?.currentHearts == 3)
    }

    @Test func practiceWithZeroHeartsIncorrectDoesNotGoNegative() throws {
        let f = try makeFixture(initialHearts: 0)
        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)

        vm.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        vm.submitAndAdvance(.incorrect(canonicalAnswer: "a"))

        #expect(vm.remainingHearts == 0)
        #expect(vm.phase == .playing)
    }

    // MARK: - Depleted phase

    @Test func practiceNeverEntersDepletedPhase() throws {
        let f = try makeFixture(initialHearts: 1)
        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)

        vm.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        #expect(vm.phase == .playing)
        vm.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        #expect(vm.phase == .playing)
        vm.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        // All exercises answered → completed, not depleted.
        #expect(vm.phase != .depleted)
    }

    // MARK: - Gamification: XP

    @Test func practiceAwardsXP() throws {
        let f = try makeFixture(initialHearts: 5)
        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)
        completeAll(vm, results: [.correct, .correct, .incorrect(canonicalAnswer: "a")])

        guard case .completed(let outcome) = vm.phase else {
            Issue.record("Expected completed phase")
            return
        }
        #expect(outcome.isPractice == true)
        #expect(outcome.xpEarned == 20) // 2 correct × 10 XP
        #expect(f.user.progress?.xp == 20)
    }

    // MARK: - Gamification: no gems

    @Test func practiceDoesNotAwardGems() throws {
        let f = try makeFixture(initialHearts: 5, gems: 0)
        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)
        completeAll(vm, results: [.correct, .correct, .correct])

        #expect(f.user.progress?.gems == 0)
    }

    // MARK: - Gamification: no lesson counter

    @Test func practiceDoesNotIncrementTotalLessonsCompleted() throws {
        let f = try makeFixture(initialHearts: 5)
        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)
        completeAll(vm, results: [.correct, .correct, .correct])

        #expect(f.user.progress?.totalLessonsCompleted == 0)
    }

    // MARK: - Gamification: no streak

    @Test func practiceDoesNotAdvanceStreak() throws {
        let f = try makeFixture(initialHearts: 5)
        f.user.progress?.streak?.currentStreak = 0
        try f.context.save()

        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)
        completeAll(vm, results: [.correct, .correct, .correct])

        #expect(f.user.progress?.streak?.currentStreak == 0)
    }

    // MARK: - Gamification: no achievements

    @Test func practiceDoesNotAwardCompletionAchievements() throws {
        let f = try makeFixture(initialHearts: 5)
        try AchievementBootstrap.bootstrapIfNeeded(context: f.context)

        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)
        completeAll(vm, results: [.correct, .correct, .correct])

        let earned = try f.achievementRepository.fetchEarnedKeys(for: f.user)
        #expect(!earned.contains("first_lesson"))
    }

    // MARK: - Gamification: no daily goal update

    @Test func practiceDoesNotUpdateDailyGoal() throws {
        let f = try makeFixture(initialHearts: 5)
        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)
        completeAll(vm, results: [.correct, .correct, .correct])

        #expect(f.user.progress?.dailyGoal?.xpEarnedToday == 0)
    }

    // MARK: - Gamification: no correct/answered counter increment

    @Test func practiceDoesNotIncrementCorrectAnsweredCounters() throws {
        let f = try makeFixture(initialHearts: 5)
        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)
        completeAll(vm, results: [.correct, .correct, .incorrect(canonicalAnswer: "a")])

        #expect(f.user.progress?.totalCorrectAnswers == 0)
        #expect(f.user.progress?.totalExercisesAnswered == 0)
    }

    // MARK: - Lesson progress: attempts and bestAccuracy

    @Test func practiceUpdatesAttemptsAndBestAccuracy() throws {
        let f = try makeFixture(initialHearts: 5)
        // Pre-mark the lesson as completed with 0.5 accuracy.
        let progress = LessonProgress(status: .completed, user: f.user, lesson: f.lesson)
        progress.bestAccuracy = 0.5
        progress.attempts = 1
        f.context.insert(progress)
        try f.context.save()

        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)
        completeAll(vm, results: [.correct, .correct, .correct]) // accuracy 1.0

        let lessonID = f.lesson.id
        let predicate = #Predicate<LessonProgress> { $0.lesson?.id == lessonID }
        let progresses = try f.context.fetch(FetchDescriptor<LessonProgress>(predicate: predicate))
        #expect(progresses.count == 1)
        let lp = try #require(progresses.first)
        #expect(lp.attempts == 2) // was 1, practice incremented
        #expect(lp.bestAccuracy == 1.0) // was 0.5, improved to 1.0
    }

    @Test func practiceDoesNotDegradeBestAccuracy() throws {
        let f = try makeFixture(initialHearts: 5)
        let progress = LessonProgress(status: .completed, user: f.user, lesson: f.lesson)
        progress.bestAccuracy = 1.0
        progress.attempts = 1
        f.context.insert(progress)
        try f.context.save()

        let vm = makeViewModel(f, mode: .practice)
        vm.load(lessonID: f.lesson.id, mode: .practice)
        completeAll(vm, results: [.incorrect(canonicalAnswer: "a"), .incorrect(canonicalAnswer: "a"), .incorrect(canonicalAnswer: "a")])

        let lessonID = f.lesson.id
        let predicate = #Predicate<LessonProgress> { $0.lesson?.id == lessonID }
        let lp = try f.context.fetch(FetchDescriptor<LessonProgress>(predicate: predicate)).first
        #expect(lp?.bestAccuracy == 1.0) // preserved
    }

    // MARK: - Normal mode regression: hearts still decrement

    @Test func normalModeIncorrectStillDecrementsHearts() throws {
        let f = try makeFixture(initialHearts: 5)
        let vm = makeViewModel(f, mode: .normal)
        vm.load(lessonID: f.lesson.id, mode: .normal)

        vm.submitAndAdvance(.incorrect(canonicalAnswer: "a"))

        #expect(vm.remainingHearts == 4)
        #expect(try f.heartsRepository.fetchHearts(for: f.user)?.currentHearts == 4)
    }

    @Test func normalModeAwardsFullGamification() throws {
        let f = try makeFixture(initialHearts: 5, gems: 0)
        try AchievementBootstrap.bootstrapIfNeeded(context: f.context)

        let vm = makeViewModel(f, mode: .normal)
        vm.load(lessonID: f.lesson.id, mode: .normal)
        completeAll(vm, results: [.correct, .correct, .correct])

        #expect(f.user.progress?.xp == 30)
        #expect(f.user.progress?.gems == 5)
        #expect(f.user.progress?.totalLessonsCompleted == 1)
        #expect(f.user.progress?.streak?.currentStreak == 1)
        #expect(f.user.progress?.dailyGoal?.xpEarnedToday == 30)
        let earned = try f.achievementRepository.fetchEarnedKeys(for: f.user)
        #expect(earned.contains("first_lesson"))
    }

    @Test func normalModeOutcomeIsNotPractice() throws {
        let f = try makeFixture(initialHearts: 5)
        let vm = makeViewModel(f, mode: .normal)
        vm.load(lessonID: f.lesson.id, mode: .normal)
        completeAll(vm, results: [.correct, .correct, .correct])

        guard case .completed(let outcome) = vm.phase else {
            Issue.record("Expected completed phase")
            return
        }
        #expect(outcome.isPractice == false)
    }

    // MARK: - CourseMapViewModel: session mode selection

    private struct CourseMapFixture {
        let context: ModelContext
        let repository: LessonProgressRepository
        let heartsRepository: HeartsRepository
        let viewModel: CourseMapViewModel
        let lessons: [Lesson]
    }

    private func makeCourseMapFixture(hearts: Int = 5, completedIndices: [Int] = []) throws -> CourseMapFixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        let heartsRow = Hearts(currentHearts: hearts, maxHearts: 5, user: user)
        context.insert(heartsRow)

        let course = Course(key: "course.ru-tr", titleKey: "course.ru-tr.title")
        context.insert(course)
        let level = Level(key: "a1", cefr: .a1, orderIndex: 0, course: course)
        context.insert(level)
        let unit = Miko.Unit(key: "a1.u1", orderIndex: 0, titleKey: "unit.a1.u1.title", theme: "theme", summaryKey: "unit.a1.u1.summary", level: level)
        context.insert(unit)

        var lessons: [Lesson] = []
        for i in 0..<3 {
            let lesson = Lesson(key: "a1.u1.l\(i + 1)", orderIndex: i, titleKey: "lesson.a1.u1.l\(i + 1).title", kind: .skill, unit: unit)
            context.insert(lesson)
            lessons.append(lesson)
        }
        for i in completedIndices {
            let lp = LessonProgress(status: .completed, user: user, lesson: lessons[i])
            lp.bestAccuracy = 1.0
            context.insert(lp)
        }
        try context.save()

        let repo = LessonProgressRepository(context: context)
        let heartsRepo = HeartsRepository(context: context)
        let vm = CourseMapViewModel(
            repository: repo,
            heartsRepository: heartsRepo,
            gamificationRepository: nil
        )
        vm.load()
        return CourseMapFixture(
            context: context,
            repository: repo,
            heartsRepository: heartsRepo,
            viewModel: vm,
            lessons: lessons
        )
    }

    @Test func completedLessonLaunchesInPracticeMode() throws {
        let f = try makeCourseMapFixture(completedIndices: [0])
        let snapshot = try #require(f.viewModel.snapshot)
        let firstNode = snapshot.allLessons[0]

        f.viewModel.select(firstNode)

        #expect(f.viewModel.requestedLessonID == firstNode.id)
        #expect(f.viewModel.requestedMode == .practice)
    }

    @Test func unlockedUnfinishedLessonLaunchesInNormalMode() throws {
        let f = try makeCourseMapFixture(completedIndices: [0])
        let snapshot = try #require(f.viewModel.snapshot)
        // Lesson 1 is unlocked (previous completed) but not completed.
        let secondNode = snapshot.allLessons[1]

        f.viewModel.select(secondNode)

        #expect(f.viewModel.requestedLessonID == secondNode.id)
        #expect(f.viewModel.requestedMode == .normal)
    }

    @Test func lockedLessonDoesNotLaunch() throws {
        let f = try makeCourseMapFixture(completedIndices: [])
        let snapshot = try #require(f.viewModel.snapshot)
        // Lesson 2 is locked (lesson 1 not completed).
        let lockedNode = snapshot.allLessons[2]

        f.viewModel.select(lockedNode)

        #expect(f.viewModel.requestedLessonID == nil)
    }

    @Test func practiceModeBypassesHeartsCheckInCourseMap() throws {
        let f = try makeCourseMapFixture(hearts: 0, completedIndices: [0])
        #expect(f.viewModel.canPlay == false)

        let snapshot = try #require(f.viewModel.snapshot)
        let completedNode = snapshot.allLessons[0]

        // Even with 0 hearts, completed lessons can be selected for practice.
        f.viewModel.select(completedNode)

        #expect(f.viewModel.requestedLessonID == completedNode.id)
        #expect(f.viewModel.requestedMode == .practice)
    }

    @Test func normalModeBlockedByZeroHeartsInCourseMap() throws {
        let f = try makeCourseMapFixture(hearts: 0, completedIndices: [0])
        #expect(f.viewModel.canPlay == false)

        let snapshot = try #require(f.viewModel.snapshot)
        let unlockedNode = snapshot.allLessons[1]

        // With 0 hearts, normal (unlocked) lessons cannot be selected.
        f.viewModel.select(unlockedNode)

        #expect(f.viewModel.requestedLessonID == nil)
    }

    @Test func consumeRequestClearsMode() throws {
        let f = try makeCourseMapFixture(completedIndices: [0])
        let snapshot = try #require(f.viewModel.snapshot)
        f.viewModel.select(snapshot.allLessons[0])
        #expect(f.viewModel.requestedMode == .practice)

        f.viewModel.consumeRequest()

        #expect(f.viewModel.requestedLessonID == nil)
        #expect(f.viewModel.requestedMode == .normal)
    }
}
