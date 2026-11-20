import Foundation
import Observation

/// Distinguishes a normal lesson completion attempt from a practice replay
/// of an already-completed lesson. Practice mode does not consume hearts and
/// does not trigger normal lesson-completion gamification (streak, gems,
/// lesson counter, achievements). XP is still awarded.
enum LessonSessionMode: Equatable, Sendable {
    case normal
    case practice
}

/// Drives the playable lesson flow: sequencing exercises, counting results,
/// and persisting progress on completion. Transient state lives here — never
/// in the SwiftUI views. Sequencing decisions belong exclusively to this class;
/// exercise views only report their result.
@MainActor
@Observable
final class LessonFlowViewModel {

    /// Final stats of a finished lesson run.
    struct LessonOutcome: Equatable {
        let lessonTitle: String
        let correctCount: Int
        let totalCount: Int
        let accuracy: Double
        let xpEarned: Int
        /// True when this was a practice replay of a completed lesson.
        let isPractice: Bool
    }

    enum Phase: Equatable {
        case loading
        case playing
        case completed(LessonOutcome)
        case failed(String)
        /// Hearts ran out mid-lesson. The user can leave the lesson; no further
        /// progression is allowed.
        case depleted
    }

    enum FlowError: Error, Equatable {
        case missingLesson
        case emptyLesson
        case malformedContent
        case noHearts
    }

    // MARK: - State

    private(set) var phase: Phase = .loading
    private(set) var exercises: [Exercise] = []
    private(set) var currentIndex: Int = 0
    /// Result of the current exercise, nil until the user acknowledges feedback.
    private(set) var currentResult: ExerciseResult?
    private(set) var correctCount: Int = 0
    private(set) var incorrectCount: Int = 0

    /// True when persistence of the finished run failed. The run still counts;
    /// the results screen surfaces a non-blocking warning.
    private(set) var persistenceFailed: Bool = false

    /// Current heart count for the lesson. Backed by the persistent `Hearts`
    /// row via `HeartsRepository`; falls back to a placeholder when no
    /// repository is supplied (legacy tests).
    private(set) var remainingHearts: Int = 5
    private(set) var totalHearts: Int = 5
    private(set) var audioEnabled = true
    private(set) var soundOn = true

    /// Current session mode — `.normal` by default, set to `.practice` when
    /// replaying a completed lesson. Controls hearts consumption and which
    /// gamification pipeline runs on completion.
    private(set) var sessionMode: LessonSessionMode = .normal

    private let repository: LessonProgressRepository
    private let heartsRepository: HeartsRepository?
    private let gamificationService: GamificationService?
    private var lesson: Lesson?
    private var answeredKeys: Set<String> = []
    private var results: [ExerciseResult] = []
    private var lastSubmitAt: Date?
    private var completionID: UUID = UUID()

    /// Guards against a double-tap on Continue being counted as an answer for
    /// the next exercise. Tests drive answers programmatically and pass 0.
    private let duplicateSubmissionWindow: TimeInterval

    init(
        repository: LessonProgressRepository,
        heartsRepository: HeartsRepository? = nil,
        gamificationService: GamificationService? = nil,
        duplicateSubmissionWindow: TimeInterval = 0.3
    ) {
        self.repository = repository
        self.heartsRepository = heartsRepository
        self.gamificationService = gamificationService
        self.duplicateSubmissionWindow = duplicateSubmissionWindow
    }

    // MARK: - Derived state

    var currentExercise: Exercise? {
        guard exercises.indices.contains(currentIndex) else { return nil }
        return exercises[currentIndex]
    }

    var answeredCount: Int {
        correctCount + incorrectCount
    }

    var totalCount: Int {
        exercises.count
    }

    /// Accuracy over answered exercises so far (0...1).
    var accuracy: Double {
        guard answeredCount > 0 else { return 0 }
        return Double(correctCount) / Double(answeredCount)
    }

    /// Overall progress through the lesson (0...1), counting the exercise
    /// currently being answered.
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(currentIndex) / Double(totalCount)
    }

    /// Whether the lesson offers a grammar reference sheet.
    var grammarTopic: GrammarTopic? {
        lesson?.grammarTopics.first
    }

    /// Seconds until the next heart regenerates, for the depleted overlay.
    /// Returns 0 when no hearts repository is available or hearts are full.
    var secondsUntilNextHeart: TimeInterval {
        guard let heartsRepository,
              let user = try? repository.fetchPrimaryUserProfile() else { return 0 }
        return (try? heartsRepository.secondsUntilNextHeart(for: user)) ?? 0
    }

    // MARK: - Loading

    func load(lessonID: UUID, mode: LessonSessionMode = .normal) {
        phase = .loading
        sessionMode = mode
        do {
            guard let lesson = try repository.fetchLesson(id: lessonID) else {
                phase = .failed(String(localized: "lessonflow.error.missingLesson"))
                return
            }
            self.lesson = lesson

            if let user = try? repository.fetchPrimaryUserProfile() {
                audioEnabled = user.settings?.audioEnabled ?? true
                soundOn = user.settings?.soundOn ?? true
            }

            let playable = try repository.fetchExercises(for: lesson)
                .filter(Self.isPlayable)
                // Never leave the learner guessing blindly. When exercise
                // audio is explicitly disabled, listening-only questions are
                // omitted while the rest of the lesson remains playable.
                .filter { audioEnabled || $0.type != .listeningComprehension }
            guard !playable.isEmpty else {
                phase = .failed(String(localized: "lessonflow.error.emptyLesson"))
                return
            }

            // Refresh hearts from the persistent store (with lazy regeneration)
            // and refuse to start when the user has none left. Practice mode
            // bypasses this check — completed lessons can be replayed with 0
            // hearts.
            if let heartsRepository,
               let user = try? repository.fetchPrimaryUserProfile() {
                _ = try? heartsRepository.regenerateIfNeeded(for: user)
                if let hearts = try? heartsRepository.fetchHearts(for: user) {
                    totalHearts = hearts.maxHearts
                    remainingHearts = hearts.currentHearts
                }
                if mode == .normal && remainingHearts <= 0 {
                    phase = .failed(String(localized: "lessonflow.error.noHearts"))
                    return
                }
            }

            exercises = playable
            currentIndex = 0
            currentResult = nil
            correctCount = 0
            incorrectCount = 0
            answeredKeys = []
            results = []
            lastSubmitAt = nil
            persistenceFailed = false
            completionID = UUID()
            phase = .playing
        } catch {
            phase = .failed(String(localized: "lessonflow.error.loadFailed"))
        }
    }

    /// An exercise is playable when its payload decodes if the type requires
    /// structured payload data. Malformed exercises are dropped instead of
    /// crashing or blocking the flow.
    static func isPlayable(_ exercise: Exercise) -> Bool {
        switch exercise.type {
        case .multipleChoice:
            return ExerciseFactory.decodePayload(MultipleChoicePayload.self, from: exercise) != nil
        case .listeningComprehension:
            return ExerciseFactory.decodePayload(ListeningComprehensionPayload.self, from: exercise) != nil
        case .buildSentence:
            return ExerciseFactory.decodePayload(BuildSentencePayload.self, from: exercise) != nil
        case .matchPairs:
            return ExerciseFactory.decodePayload(MatchPairsPayload.self, from: exercise) != nil
        case .fillBlank:
            return ExerciseFactory.decodePayload(FillBlankPayload.self, from: exercise) != nil
        case .vocabularyReview:
            return !exercise.vocabulary.isEmpty || !(exercise.lesson?.vocabulary.isEmpty ?? true)
        case .translateWord, .translateSentence, .pronunciation:
            return true
        }
    }

    // MARK: - Answer handling

    /// Called by exercise views when the user has seen feedback and tapped
    /// Continue. Records the result, then advances or finishes the lesson.
    /// Duplicate submissions for the same exercise are ignored.
    func submit(_ result: ExerciseResult) {
        guard phase == .playing,
              let exercise = currentExercise,
              !answeredKeys.contains(exercise.key) else { return }

        if let lastSubmitAt,
           Date().timeIntervalSince(lastSubmitAt) < duplicateSubmissionWindow {
            return
        }

        lastSubmitAt = Date()
        answeredKeys.insert(exercise.key)
        results.append(result)
        currentResult = result

        switch result {
        case .correct:
            correctCount += 1
        case .incorrect:
            incorrectCount += 1
            // Practice mode does not consume hearts.
            if sessionMode == .normal {
                var hapticsEnabled = true
                if let heartsRepository,
                   let user = try? repository.fetchPrimaryUserProfile() {
                    remainingHearts = (try? heartsRepository.decrementHeart(for: user)) ?? remainingHearts
                    hapticsEnabled = user.settings?.hapticsEnabled ?? true
                } else {
                    remainingHearts = max(0, remainingHearts - 1)
                }
                Haptics.heartLost(enabled: hapticsEnabled)
            }
        case .skipped:
            // Infrastructure/permission failure: advance without awarding XP
            // or charging a heart for an answer the learner could not give.
            break
        }
    }

    /// Advances to the next exercise or finishes the lesson. No-op before an
    /// answer has been submitted for the current exercise.
    func advance() {
        guard phase == .playing, currentResult != nil else { return }

        // Stop progression when the user is out of hearts (normal mode only).
        if sessionMode == .normal && remainingHearts <= 0 {
            phase = .depleted
            return
        }

        if currentIndex + 1 < exercises.count {
            currentIndex += 1
            currentResult = nil
        } else {
            finish()
        }
    }

    /// Convenience for exercise views: record the result, then move on as soon
    /// as feedback has been acknowledged.
    func submitAndAdvance(_ result: ExerciseResult) {
        submit(result)
        advance()
    }

    // MARK: - Completion

    private func finish() {
        let accuracy = totalCount > 0 ? Double(correctCount) / Double(totalCount) : 0
        let xpEarned: Int
        if gamificationService != nil {
            // The service awards XP persistently; the outcome's xpEarned
            // mirrors what was banked so the results screen shows the real
            // persisted value.
            xpEarned = correctCount * GamificationService.xpPerCorrect
        } else {
            // No service (e.g. legacy test fixture) — keep the same rule.
            xpEarned = correctCount * Self.legacyXpPerCorrect
        }
        let outcome = LessonOutcome(
            lessonTitle: lesson.map { localizedTitle(for: $0) } ?? "",
            correctCount: correctCount,
            totalCount: totalCount,
            accuracy: accuracy,
            xpEarned: xpEarned,
            isPractice: sessionMode == .practice
        )

        persist(lesson: lesson, exercises: exercises, results: results, accuracy: accuracy)
        phase = .completed(outcome)
    }

    /// Legacy XP rule retained for tests that construct the ViewModel without
    /// a `GamificationService`. Production code passes a service and uses
    /// `GamificationService.xpPerCorrect`.
    static let legacyXpPerCorrect = 10

    private func persist(lesson: Lesson?, exercises: [Exercise], results: [ExerciseResult], accuracy: Double) {
        guard let lesson,
              let user = try? repository.fetchPrimaryUserProfile() else {
            persistenceFailed = true
            return
        }
        do {
            // Both normal and practice sessions record the attempt and update
            // bestAccuracy / exercise progress. Practice does not create a
            // new completion — it updates the existing record.
            let lessonProgress = try repository.recordCompletion(
                user: user,
                lesson: lesson,
                exercises: exercises,
                results: results,
                accuracy: accuracy
            )
            // Apply the gamification pipeline. Normal mode runs the full
            // pipeline (XP, counters, daily goal, streak, achievements, gems).
            // Practice mode only awards XP — no counters, streak, gems, or
            // achievement re-evaluation.
            if let gamificationService {
                switch sessionMode {
                case .normal:
                    _ = try gamificationService.applyLessonCompletion(
                        user: user,
                        correctCount: correctCount,
                        answeredCount: answeredCount,
                        completionID: completionID
                    )
                case .practice:
                    _ = try gamificationService.applyPracticeCompletion(
                        user: user,
                        correctCount: correctCount
                    )
                }
            }
            _ = lessonProgress
        } catch {
            persistenceFailed = true
        }
    }

    private func localizedTitle(for lesson: Lesson) -> String {
        let key = String.LocalizationValue(lesson.titleKey)
        return String(localized: key)
    }
}
