import Foundation
import Observation
import Synchronization
import SwiftData
import Testing
@testable import Miko

/// Focused regression tests for the hearts bug: starting with 5/5 hearts,
/// one incorrect answer must result in 4/5 and the lesson continues — NOT
/// the depleted screen. Also covers the upgrade scenario where a
/// pre-Phase-5 `UserProfile` exists without a `Hearts` row.
@MainActor
struct HeartsBugRegressionTests {

    private struct Fixture {
        let context: ModelContext
        let repository: LessonProgressRepository
        let heartsRepository: HeartsRepository
        let user: UserProfile
        let lesson: Lesson
    }

    /// Builds a fixture with a real `Hearts` row (fresh-install scenario).
    private func makeFixture(initialHearts: Int = 5) throws -> Fixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        let hearts = Hearts(currentHearts: initialHearts, maxHearts: 5, user: user)
        context.insert(hearts)
        let lesson = Lesson(key: "a1.u1.l1", orderIndex: 0, titleKey: "t", kind: .skill)
        context.insert(lesson)
        for index in 0..<5 {
            let exercise = Exercise(
                key: "e\(index)", orderIndex: index, type: .translateWord,
                promptText: "p", payloadData: nil,
                correctAnswerText: "a", acceptedAnswers: ["a"], lesson: lesson
            )
            context.insert(exercise)
        }
        try context.save()
        return Fixture(
            context: context,
            repository: LessonProgressRepository(context: context),
            heartsRepository: HeartsRepository(context: context),
            user: user,
            lesson: lesson
        )
    }

    /// Builds a fixture that simulates a pre-Phase-5 upgrade: `UserProfile`
    /// exists but there is NO `Hearts` row.
    private func makeUpgradeFixture() throws -> Fixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        // Deliberately do NOT insert a Hearts row.
        let lesson = Lesson(key: "a1.u1.l1", orderIndex: 0, titleKey: "t", kind: .skill)
        context.insert(lesson)
        for index in 0..<5 {
            let exercise = Exercise(
                key: "e\(index)", orderIndex: index, type: .translateWord,
                promptText: "p", payloadData: nil,
                correctAnswerText: "a", acceptedAnswers: ["a"], lesson: lesson
            )
            context.insert(exercise)
        }
        try context.save()
        return Fixture(
            context: context,
            repository: LessonProgressRepository(context: context),
            heartsRepository: HeartsRepository(context: context),
            user: user,
            lesson: lesson
        )
    }

    private func makeViewModel(_ fixture: Fixture) -> LessonFlowViewModel {
        LessonFlowViewModel(
            repository: fixture.repository,
            heartsRepository: fixture.heartsRepository,
            gamificationService: nil,
            duplicateSubmissionWindow: 0
        )
    }

    // MARK: - Home timer refresh

    @Test func homeRefreshUpdatesCountdownAndReenablesLessonAfterRegeneration() throws {
        let fixture = try makeFixture(initialHearts: 0)
        let progress = UserProgress()
        progress.user = fixture.user
        fixture.context.insert(progress)
        let hearts = try #require(try fixture.heartsRepository.fetchHearts(for: fixture.user))
        hearts.lastRegeneratedAt = Date().addingTimeInterval(-120)
        try fixture.context.save()
        let viewModel = HomeViewModel(
            repository: fixture.repository,
            heartsRepository: fixture.heartsRepository
        )

        viewModel.load()
        let originalStats = viewModel.stats
        let originalCountdown = viewModel.secondsUntilNextHeart
        #expect(originalCountdown > 1600)
        #expect(!viewModel.canStartLesson)

        // The countdown must refresh even while the stats snapshot is identical.
        hearts.lastRegeneratedAt = hearts.lastRegeneratedAt.addingTimeInterval(-60)
        try fixture.context.save()
        let countdownChanged = Mutex(false)
        withObservationTracking {
            _ = viewModel.secondsUntilNextHeart
        } onChange: {
            countdownChanged.withLock { $0 = true }
        }
        viewModel.load()
        #expect(countdownChanged.withLock { $0 })
        #expect(viewModel.stats == originalStats)
        #expect(viewModel.secondsUntilNextHeart < originalCountdown - 59)

        hearts.lastRegeneratedAt = Date().addingTimeInterval(
            -HeartsRepository.regenerationInterval - 5
        )
        try fixture.context.save()
        viewModel.load()
        #expect(viewModel.stats?.heartsRemaining == 1)
        #expect(viewModel.canStartLesson)
        #expect(viewModel.stats?.xp == 0)
    }

    // MARK: - Core regression: 5 → 4 + continues

    @Test func incorrectAnswerWith5HeartsGoesTo4AndContinues() throws {
        let fixture = try makeFixture(initialHearts: 5)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        #expect(viewModel.remainingHearts == 5)
        #expect(viewModel.phase == .playing)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "a"))

        #expect(viewModel.remainingHearts == 4)
        #expect(viewModel.phase == .playing)
        #expect(viewModel.currentIndex == 1)
    }

    // MARK: - 1 → 0 + depleted

    @Test func incorrectAnswerWith1HeartGoesTo0AndDepletes() throws {
        let fixture = try makeFixture(initialHearts: 1)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "a"))

        #expect(viewModel.remainingHearts == 0)
        #expect(viewModel.phase == .depleted)
    }

    // MARK: - Correct answer → unchanged

    @Test func correctAnswerDoesNotChangeHearts() throws {
        let fixture = try makeFixture(initialHearts: 3)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submitAndAdvance(.correct)

        #expect(viewModel.remainingHearts == 3)
        #expect(viewModel.phase == .playing)
        #expect(viewModel.currentIndex == 1)
    }

    // MARK: - Multiple incorrect → one at a time

    @Test func multipleIncorrectAnswersDecrementOneAtATime() throws {
        let fixture = try makeFixture(initialHearts: 5)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        #expect(viewModel.remainingHearts == 4)
        #expect(viewModel.phase == .playing)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        #expect(viewModel.remainingHearts == 3)
        #expect(viewModel.phase == .playing)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        #expect(viewModel.remainingHearts == 2)
        #expect(viewModel.phase == .playing)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        #expect(viewModel.remainingHearts == 1)
        #expect(viewModel.phase == .playing)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "a"))
        #expect(viewModel.remainingHearts == 0)
        #expect(viewModel.phase == .depleted)
    }

    // MARK: - Never negative

    @Test func heartsNeverGoNegative() throws {
        let fixture = try makeFixture(initialHearts: 1)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submit(.incorrect(canonicalAnswer: "a"))
        #expect(viewModel.remainingHearts == 0)

        // Already at 0 — another incorrect (on a new exercise) can't go below.
        // The depleted phase stops progression, but verify the value is ≥ 0.
        #expect(viewModel.remainingHearts >= 0)
    }

    // MARK: - Upgrade scenario: no Hearts row → decrementHeart creates it

    @Test func upgradeScenarioFirstIncorrectDoesNotFalselyDeplete() throws {
        let fixture = try makeUpgradeFixture()
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        // Lesson starts (no Hearts row, remainingHearts defaults to 5).
        #expect(viewModel.phase == .playing)
        #expect(viewModel.remainingHearts == 5)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "a"))

        // Must be 4 (not 0!) and the lesson must continue.
        #expect(viewModel.remainingHearts == 4)
        #expect(viewModel.phase == .playing)
        #expect(viewModel.currentIndex == 1)

        // The Hearts row should now exist in the store.
        let hearts = try fixture.heartsRepository.fetchHearts(for: fixture.user)
        #expect(hearts != nil)
        #expect(hearts?.currentHearts == 4)
        #expect(hearts?.maxHearts == 5)
    }

    // MARK: - decrementHeart directly

    @Test func decrementHeartCreatesHeartsRowWhenMissing() throws {
        let fixture = try makeUpgradeFixture()
        // No Hearts row initially.
        #expect(try fixture.heartsRepository.fetchHearts(for: fixture.user) == nil)

        let result = try fixture.heartsRepository.decrementHeart(for: fixture.user)
        #expect(result == 4) // defaultMax (5) - 1

        let hearts = try fixture.heartsRepository.fetchHearts(for: fixture.user)
        #expect(hearts?.currentHearts == 4)
        #expect(hearts?.maxHearts == 5)
    }

    // MARK: - Persisted value matches displayed value

    @Test func displayedHeartsMatchesPersistedValue() throws {
        let fixture = try makeFixture(initialHearts: 5)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "a"))

        let persisted = try fixture.heartsRepository.fetchHearts(for: fixture.user)?.currentHearts
        #expect(viewModel.remainingHearts == persisted)
        #expect(persisted == 4)
    }

    // MARK: - UserBootstrap creates Hearts for existing users

    @Test func userBootstrapCreatesHeartsForExistingUserProfile() throws {
        let suiteName = "MikoTests.legacy-bootstrap.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Simulate pre-Phase-5: create UserProfile without Hearts.
        let user = UserProfile(username: "old", avatar: "")
        context.insert(user)
        try context.save()

        // Now run bootstrap — it should add the missing Hearts row.
        try UserBootstrap.bootstrapIfNeeded(context: context, defaults: defaults)

        let hearts = try context.fetch(FetchDescriptor<Hearts>())
        #expect(hearts.count == 1)
        #expect(hearts.first?.currentHearts == 5)
        #expect(hearts.first?.maxHearts == 5)
        #expect(hearts.first?.user?.id == user.id)
    }

    @Test func userBootstrapIsIdempotentForHeartsCreation() throws {
        let suiteName = "MikoTests.bootstrap-idempotence.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "old", avatar: "")
        context.insert(user)
        try context.save()

        try UserBootstrap.bootstrapIfNeeded(context: context, defaults: defaults)
        try UserBootstrap.bootstrapIfNeeded(context: context, defaults: defaults)
        try UserBootstrap.bootstrapIfNeeded(context: context, defaults: defaults)

        let hearts = try context.fetch(FetchDescriptor<Hearts>())
        #expect(hearts.count == 1) // no duplicates
        #expect(hearts.first?.user?.id == user.id)
    }
}
