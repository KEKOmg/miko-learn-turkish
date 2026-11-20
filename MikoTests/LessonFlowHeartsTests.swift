import Foundation
import SwiftData
import Testing
@testable import Miko

/// Tests for the hearts integration in `LessonFlowViewModel`: incorrect
/// answers decrement hearts, the flow blocks when hearts reach 0, and
/// starting a lesson with 0 hearts fails.
@MainActor
struct LessonFlowHeartsTests {

    private struct Fixture {
        let context: ModelContext
        let repository: LessonProgressRepository
        let heartsRepository: HeartsRepository
        let user: UserProfile
        let lesson: Lesson
    }

    private func makeFixture(initialHearts: Int = 5) throws -> Fixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)

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

    // MARK: - Loading / start

    @Test func loadReadsHeartsFromStore() throws {
        let fixture = try makeFixture(initialHearts: 3)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        #expect(viewModel.phase == .playing)
        #expect(viewModel.remainingHearts == 3)
        #expect(viewModel.totalHearts == 5)
    }

    @Test func loadFailsWhenHeartsZero() throws {
        let fixture = try makeFixture(initialHearts: 0)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        guard case .failed = viewModel.phase else {
            Issue.record("Expected failed phase when hearts == 0")
            return
        }
    }

    // MARK: - Decrement on incorrect

    @Test func incorrectAnswerDecrementsHeart() throws {
        let fixture = try makeFixture(initialHearts: 5)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submit(.incorrect(canonicalAnswer: "Merhaba"))

        #expect(viewModel.incorrectCount == 1)
        #expect(viewModel.remainingHearts == 4)
        // Persisted too.
        #expect(try fixture.heartsRepository.fetchHearts(for: fixture.user)?.currentHearts == 4)
    }

    @Test func correctAnswerDoesNotDecrement() throws {
        let fixture = try makeFixture(initialHearts: 5)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submit(.correct)

        #expect(viewModel.remainingHearts == 5)
        #expect(try fixture.heartsRepository.fetchHearts(for: fixture.user)?.currentHearts == 5)
    }

    // MARK: - Depletion

    @Test func advancingWithZeroHeartsEntersDepletedPhase() throws {
        let fixture = try makeFixture(initialHearts: 1)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "Merhaba"))

        #expect(viewModel.remainingHearts == 0)
        #expect(viewModel.phase == .depleted)
    }

    @Test func depletedPhaseStopsProgression() throws {
        let fixture = try makeFixture(initialHearts: 1)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "Merhaba"))
        #expect(viewModel.phase == .depleted)

        // Advancing from depleted is a no-op.
        viewModel.advance()
        #expect(viewModel.phase == .depleted)
        #expect(viewModel.currentIndex == 0)
    }

    @Test func heartsNeverGoNegative() throws {
        let fixture = try makeFixture(initialHearts: 1)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submit(.incorrect(canonicalAnswer: "Merhaba"))
        viewModel.submit(.incorrect(canonicalAnswer: "Merhaba"))

        // Second incorrect is a duplicate-submission guard (same exercise),
        // so only one decrement happens. But hearts is already 0.
        #expect(viewModel.remainingHearts >= 0)
    }

    // MARK: - Happy path with hearts

    @Test func completingLessonWithFullHeartsDoesNotLoseAny() throws {
        let fixture = try makeFixture(initialHearts: 5)
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submitAndAdvance(.correct)
        viewModel.submitAndAdvance(.correct)
        viewModel.submitAndAdvance(.correct)

        guard case .completed = viewModel.phase else {
            Issue.record("Expected completed phase")
            return
        }
        #expect(viewModel.remainingHearts == 5)
    }

    // MARK: - Regeneration on load

    @Test func loadRegeneratesHeartsBeforeStarting() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        // 1 heart, last regenerated 60 minutes ago → load() should add 2.
        let sixtyMinutesAgo = Date().addingTimeInterval(-60 * 60)
        let hearts = Hearts(
            currentHearts: 1, maxHearts: 5,
            lastRegeneratedAt: sixtyMinutesAgo, user: user
        )
        context.insert(hearts)

        let lesson = Lesson(key: "l", orderIndex: 0, titleKey: "t", kind: .skill)
        context.insert(lesson)
        let exercise = Exercise(
            key: "e", orderIndex: 0, type: .translateWord,
            promptText: "p", payloadData: nil,
            correctAnswerText: "a", acceptedAnswers: ["a"], lesson: lesson
        )
        context.insert(exercise)
        try context.save()

        let heartsRepo = HeartsRepository(context: context)
        let viewModel = LessonFlowViewModel(
            repository: LessonProgressRepository(context: context),
            heartsRepository: heartsRepo,
            duplicateSubmissionWindow: 0
        )
        viewModel.load(lessonID: lesson.id)

        #expect(viewModel.phase == .playing)
        // 60 minutes elapsed = exactly 2 regeneration intervals → 1 + 2 = 3.
        #expect(viewModel.remainingHearts == 3)
    }
}
