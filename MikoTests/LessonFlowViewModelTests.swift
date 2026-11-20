import Foundation
import SwiftData
import Testing
@testable import Miko

/// Tests for `LessonFlowViewModel`: loading, sequencing, answer handling,
/// completion stats, and progress persistence through
/// `LessonProgressRepository`.
@MainActor
struct LessonFlowViewModelTests {

    // MARK: - Fixtures

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let repository: LessonProgressRepository
        let user: UserProfile
        let lesson: Lesson
    }

    private func makeFixture(exerciseBuilders: [(String, ExerciseType)]) throws -> Fixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)

        let lesson = Lesson(key: "a1.u1.l1", orderIndex: 0, titleKey: "lesson.a1.u1.l1.title", kind: .skill)
        context.insert(lesson)

        for (index, builder) in exerciseBuilders.enumerated() {
            let (key, type) = builder
            let exercise = Exercise(
                key: key,
                orderIndex: index,
                type: type,
                promptText: "Prompt \(index)",
                payloadData: Self.payloadData(for: type, correctIndex: 0),
                correctAnswerText: "Merhaba",
                acceptedAnswers: ["merhaba"],
                lesson: lesson
            )
            context.insert(exercise)
        }
        try context.save()

        return Fixture(
            container: container,
            context: context,
            repository: LessonProgressRepository(context: context),
            user: user,
            lesson: lesson
        )
    }

    /// A decodable payload for the structured types, malformed data otherwise.
    private static func payloadData(for type: ExerciseType, correctIndex: Int) -> Data? {
        switch type {
        case .multipleChoice:
            return try? JSONEncoder().encode(MultipleChoicePayload(options: ["A", "B", "C"], correctIndex: correctIndex))
        case .listeningComprehension:
            return try? JSONEncoder().encode(ListeningComprehensionPayload(audioFileName: "a.mp3", transcript: "A", options: ["A", "B", "C"], correctIndex: correctIndex))
        case .buildSentence:
            return try? JSONEncoder().encode(BuildSentencePayload(wordBank: ["Ben", "öğrenciyim"], sentenceWords: ["Ben", "öğrenciyim"]))
        case .matchPairs:
            return try? JSONEncoder().encode(MatchPairsPayload(pairs: [MatchPair(source: "Merhaba", target: "Привет")]))
        case .fillBlank:
            return try? JSONEncoder().encode(FillBlankPayload(template: "___ günaydın", blank: "Günaydın", options: ["Günaydın", "Merhaba"]))
        case .translateWord, .translateSentence, .pronunciation, .vocabularyReview:
            return nil
        }
    }

    private func makeViewModel(_ fixture: Fixture, duplicateSubmissionWindow: TimeInterval = 0) -> LessonFlowViewModel {
        LessonFlowViewModel(
            repository: fixture.repository,
            duplicateSubmissionWindow: duplicateSubmissionWindow
        )
    }

    private func completeAll(_ viewModel: LessonFlowViewModel, results: [ExerciseResult]) {
        for result in results {
            viewModel.submitAndAdvance(result)
        }
    }

    // MARK: - Loading

    @Test func loadSetsUpOrderedExercisesAndFirstExercise() throws {
        let fixture = try makeFixture(exerciseBuilders: [
            ("e2", .translateWord), ("e1", .multipleChoice), ("e3", .fillBlank)
        ])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        #expect(viewModel.phase == .playing)
        #expect(viewModel.totalCount == 3)
        // Sorted by orderIndex = insertion order, not key order.
        #expect(viewModel.currentExercise?.key == "e2")
        #expect(viewModel.currentIndex == 0)
        #expect(viewModel.progress == 0)
    }

    @Test func missingLessonFails() throws {
        let fixture = try makeFixture(exerciseBuilders: [("e1", .multipleChoice)])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: UUID())

        guard case .failed = viewModel.phase else {
            Issue.record("Expected failed phase for missing lesson")
            return
        }
    }

    @Test func emptyLessonFails() throws {
        let fixture = try makeFixture(exerciseBuilders: [])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        guard case .failed = viewModel.phase else {
            Issue.record("Expected failed phase for empty lesson")
            return
        }
    }

    @Test func malformedPayloadExercisesAreSkipped() throws {
        let fixture = try makeFixture(exerciseBuilders: [("ok1", .translateWord), ("bad", .multipleChoice), ("ok2", .fillBlank)])
        // Corrupt the structured payload of the multiple-choice exercise.
        let bad = fixture.lesson.exercises.first { $0.key == "bad" }
        bad?.payloadData = Data("not json".utf8)
        try fixture.context.save()

        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        #expect(viewModel.phase == .playing)
        #expect(viewModel.totalCount == 2)
        #expect(viewModel.exercises.map(\.key) == ["ok1", "ok2"])
    }

    @Test func emptyVocabularyReviewIsSkippedInsteadOfBlockingLesson() throws {
        let fixture = try makeFixture(exerciseBuilders: [
            ("word", .translateWord), ("empty-review", .vocabularyReview)
        ])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        #expect(viewModel.phase == .playing)
        #expect(viewModel.exercises.map(\.key) == ["word"])
    }

    @Test func listeningExerciseIsSkippedWhenExerciseAudioIsDisabled() throws {
        let fixture = try makeFixture(exerciseBuilders: [
            ("word", .translateWord), ("listening", .listeningComprehension)
        ])
        let settings = UserSettings(audioEnabled: false, user: fixture.user)
        fixture.context.insert(settings)
        try fixture.context.save()

        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        #expect(viewModel.phase == .playing)
        #expect(viewModel.exercises.map(\.key) == ["word"])
        #expect(!viewModel.audioEnabled)
    }

    @Test func lessonWithOnlyMalformedExercisesFails() throws {
        let fixture = try makeFixture(exerciseBuilders: [("bad", .matchPairs)])
        let bad = fixture.lesson.exercises.first { $0.key == "bad" }
        bad?.payloadData = Data("{}".utf8)
        try fixture.context.save()

        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        guard case .failed = viewModel.phase else {
            Issue.record("Expected failure when all exercises are malformed")
            return
        }
    }

    // MARK: - Sequencing and answer handling

    @Test func cannotAdvanceBeforeAnswering() throws {
        let fixture = try makeFixture(exerciseBuilders: [("e1", .translateWord), ("e2", .translateWord)])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.advance()

        #expect(viewModel.currentIndex == 0)
        #expect(viewModel.currentExercise?.key == "e1")
        #expect(viewModel.phase == .playing)
    }

    @Test func submitCorrectThenAdvanceMovesToNextExercise() throws {
        let fixture = try makeFixture(exerciseBuilders: [("e1", .translateWord), ("e2", .translateWord)])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submit(.correct)
        #expect(viewModel.currentResult == .correct)
        #expect(viewModel.correctCount == 1)
        #expect(viewModel.answeredCount == 1)

        viewModel.advance()
        #expect(viewModel.currentIndex == 1)
        #expect(viewModel.currentExercise?.key == "e2")
        #expect(viewModel.currentResult == nil)
        #expect(viewModel.progress == 0.5)
    }

    @Test func submitIncorrectCountsAndAdvances() throws {
        let fixture = try makeFixture(exerciseBuilders: [("e1", .translateWord), ("e2", .translateWord)])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submitAndAdvance(.incorrect(canonicalAnswer: "Merhaba"))

        #expect(viewModel.incorrectCount == 1)
        #expect(viewModel.correctCount == 0)
        #expect(viewModel.currentIndex == 1)
    }

    @Test func unavailableSpeechCanBeSkippedWithoutHeartOrXP() throws {
        let fixture = try makeFixture(exerciseBuilders: [
            ("pronunciation", .pronunciation), ("word", .translateWord)
        ])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submitAndAdvance(.skipped)
        #expect(viewModel.currentExercise?.key == "word")
        #expect(viewModel.correctCount == 0)
        #expect(viewModel.incorrectCount == 0)
        #expect(viewModel.remainingHearts == 5)

        viewModel.submitAndAdvance(.correct)
        guard case .completed(let outcome) = viewModel.phase else {
            Issue.record("Expected lesson results after unavailable speech")
            return
        }
        #expect(outcome.xpEarned == LessonFlowViewModel.legacyXpPerCorrect)
        #expect(outcome.correctCount == 1)
        #expect(outcome.totalCount == 2)
        #expect(viewModel.answeredCount == 1, "Unavailable speech is not an answered exercise")
        #expect(viewModel.remainingHearts == 5)
        let progress = try fixture.context.fetch(FetchDescriptor<ExerciseProgress>())
        #expect(progress.count == 1)
        #expect(progress.first?.exercise?.key == "word")
    }

    @Test func duplicateSubmissionIsIgnored() throws {
        let fixture = try makeFixture(exerciseBuilders: [("e1", .translateWord), ("e2", .translateWord)])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submit(.correct)
        viewModel.submit(.correct)

        #expect(viewModel.correctCount == 1)
        #expect(viewModel.answeredCount == 1)
    }

    @Test func doubleTapOnContinueDoesNotAnswerNextExercise() throws {
        let fixture = try makeFixture(exerciseBuilders: [
            ("e1", .translateWord), ("e2", .translateWord), ("e3", .translateWord)
        ])
        // Production window: a rapid second tap (double-tap on Continue) must
        // not be counted as an answer for the freshly revealed exercise.
        let viewModel = makeViewModel(fixture, duplicateSubmissionWindow: 0.3)
        viewModel.load(lessonID: fixture.lesson.id)

        viewModel.submitAndAdvance(.correct)
        viewModel.submitAndAdvance(.correct) // double-tap — must be ignored

        #expect(viewModel.currentIndex == 1)
        #expect(viewModel.answeredCount == 1)
        #expect(viewModel.correctCount == 1)
    }

    // MARK: - Completion

    @Test func finalExerciseCompletionShowsResultsWithAccuracyAndXP() throws {
        let fixture = try makeFixture(exerciseBuilders: [
            ("e1", .translateWord), ("e2", .translateWord), ("e3", .translateWord)
        ])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        completeAll(viewModel, results: [.correct, .incorrect(canonicalAnswer: "Merhaba"), .correct])

        guard case .completed(let outcome) = viewModel.phase else {
            Issue.record("Expected completed phase")
            return
        }
        #expect(outcome.correctCount == 2)
        #expect(outcome.totalCount == 3)
        #expect(abs(outcome.accuracy - 2.0 / 3.0) < 0.0001)
        #expect(outcome.xpEarned == 20)
        #expect(!viewModel.persistenceFailed)
    }

    @Test func accuracyHelperReflectsAnsweredOnly() throws {
        let fixture = try makeFixture(exerciseBuilders: [("e1", .translateWord), ("e2", .translateWord)])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        #expect(viewModel.accuracy == 0)
        viewModel.submit(.correct)
        #expect(viewModel.accuracy == 1.0)
    }

    // MARK: - Persistence

    @Test func lessonProgressPersistedOnCompletion() throws {
        let fixture = try makeFixture(exerciseBuilders: [
            ("e1", .translateWord), ("e2", .translateWord)
        ])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)
        completeAll(viewModel, results: [.correct, .correct])

        let lessonID = fixture.lesson.id
        let descriptor = FetchDescriptor<LessonProgress>()
        let progresses = try fixture.context.fetch(descriptor).filter { $0.lesson?.id == lessonID }

        #expect(progresses.count == 1)
        let progress = try #require(progresses.first)
        #expect(progress.status == .completed)
        #expect(progress.bestAccuracy == 1.0)
        #expect(progress.attempts == 1)
        #expect(progress.lastCompletedAt != nil)
        #expect(progress.user?.id == fixture.user.id)
    }

    @Test func exerciseProgressPersistedOnCompletion() throws {
        let fixture = try makeFixture(exerciseBuilders: [
            ("e1", .translateWord), ("e2", .translateWord)
        ])
        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)
        completeAll(viewModel, results: [.correct, .incorrect(canonicalAnswer: "Merhaba")])

        let user = fixture.user
        let descriptor = FetchDescriptor<ExerciseProgress>()
        let progresses = try fixture.context.fetch(descriptor)
            .filter { $0.user?.id == user.id }
            .sorted { ($0.exercise?.orderIndex ?? 0) < ($1.exercise?.orderIndex ?? 0) }

        #expect(progresses.count == 2)
        #expect(progresses[0].correctCount == 1)
        #expect(progresses[0].incorrectCount == 0)
        #expect(progresses[0].lastResult == true)
        #expect(progresses[0].lastAnsweredAt != nil)
        #expect(progresses[1].incorrectCount == 1)
        #expect(progresses[1].lastResult == false)
        // Spaced repetition is a later phase — reviewDueAt stays untouched.
        #expect(progresses[0].reviewDueAt == nil)
        #expect(progresses[1].reviewDueAt == nil)
    }

    @Test func repeatedCompletionUpdatesSameRecordAndKeepsBestAccuracy() throws {
        let fixture = try makeFixture(exerciseBuilders: [
            ("e1", .translateWord), ("e2", .translateWord)
        ])

        // First run: perfect.
        let first = makeViewModel(fixture)
        first.load(lessonID: fixture.lesson.id)
        completeAll(first, results: [.correct, .correct])

        // Second run: worse — bestAccuracy must be preserved.
        let second = makeViewModel(fixture)
        second.load(lessonID: fixture.lesson.id)
        completeAll(second, results: [.incorrect(canonicalAnswer: "Merhaba"), .incorrect(canonicalAnswer: "Merhaba")])

        let lessonID = fixture.lesson.id
        let descriptor = FetchDescriptor<LessonProgress>()
        let progresses = try fixture.context.fetch(descriptor).filter { $0.lesson?.id == lessonID }

        #expect(progresses.count == 1) // no duplicates
        let progress = try #require(progresses.first)
        #expect(progress.attempts == 2)
        #expect(progress.bestAccuracy == 1.0)
        #expect(progress.status == .completed)
    }

    @Test func repeatedCompletionAccumulatesExerciseProgress() throws {
        let fixture = try makeFixture(exerciseBuilders: [("e1", .translateWord)])

        let first = makeViewModel(fixture)
        first.load(lessonID: fixture.lesson.id)
        completeAll(first, results: [.correct])

        let second = makeViewModel(fixture)
        second.load(lessonID: fixture.lesson.id)
        completeAll(second, results: [.incorrect(canonicalAnswer: "Merhaba")])

        let exerciseID = fixture.lesson.exercises.first?.id
        let descriptor = FetchDescriptor<ExerciseProgress>()
        let progresses = try fixture.context.fetch(descriptor).filter { $0.exercise?.id == exerciseID }

        #expect(progresses.count == 1)
        let progress = try #require(progresses.first)
        #expect(progress.correctCount == 1)
        #expect(progress.incorrectCount == 1)
        #expect(progress.lastResult == false)
    }

    // MARK: - All exercise types participate

    @Test func allNineExerciseTypesParticipateInFlow() throws {
        let types: [(String, ExerciseType)] = [
            ("e.mc", .multipleChoice),
            ("e.tw", .translateWord),
            ("e.ts", .translateSentence),
            ("e.bs", .buildSentence),
            ("e.mp", .matchPairs),
            ("e.fb", .fillBlank),
            ("e.lc", .listeningComprehension),
            ("e.pr", .pronunciation),
            ("e.vr", .vocabularyReview)
        ]
        let fixture = try makeFixture(exerciseBuilders: types)
        let reviewWord = VocabularyItem(
            key: "vocab.review.test",
            sourceText: "Привет",
            targetText: "Merhaba",
            partOfSpeech: .interjection,
            cefr: .a1
        )
        fixture.context.insert(reviewWord)
        // Deliberately keep exercise.vocabulary empty to reproduce stores
        // created before the exercise-level relationship was populated.
        fixture.lesson.vocabulary = [reviewWord]
        try fixture.context.save()

        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        #expect(viewModel.totalCount == 9)

        for _ in types {
            #expect(viewModel.phase == .playing)
            viewModel.submitAndAdvance(.correct)
        }

        guard case .completed(let outcome) = viewModel.phase else {
            Issue.record("Expected completion after all 9 exercises")
            return
        }
        #expect(outcome.correctCount == 9)
        #expect(outcome.totalCount == 9)
        #expect(outcome.accuracy == 1.0)
    }

    // MARK: - Grammar

    @Test func grammarTopicExposesFirstLessonTopic() throws {
        let fixture = try makeFixture(exerciseBuilders: [("e1", .translateWord)])
        let topic = GrammarTopic(key: "grammar.test", titleKey: "grammar.test.title", explanationKey: "grammar.test.explanation", examples: [], cefr: .a1)
        fixture.context.insert(topic)
        fixture.lesson.grammarTopics = [topic]
        try fixture.context.save()

        let viewModel = makeViewModel(fixture)
        viewModel.load(lessonID: fixture.lesson.id)

        #expect(viewModel.grammarTopic?.key == "grammar.test")
    }
}
