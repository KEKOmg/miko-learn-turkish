import SwiftUI

/// A vocabulary checkpoint in which every referenced word must be answered.
/// Revealing a translation no longer awards a correct result automatically.
struct VocabularyReviewExerciseView: View {
    private struct ReviewOption: Identifiable {
        let key: String
        let text: String

        var id: String { key }
    }

    private struct ReviewQuestion: Identifiable {
        let key: String
        let targetText: String
        let pronunciation: String
        let audioFileName: String
        let correctSourceText: String
        let options: [ReviewOption]

        var id: String { key }
    }

    let exercise: Exercise
    let audioProvider: AudioProviding
    let audioEnabled: Bool
    let onResult: @MainActor @Sendable (ExerciseResult) -> Void

    @State private var questions: [ReviewQuestion]
    @State private var currentQuestionIndex = 0
    @State private var selectedKey: String?
    @State private var state: ExerciseState = .idle
    @State private var missedAnswers: [String] = []

    init(
        exercise: Exercise,
        audioProvider: AudioProviding,
        audioEnabled: Bool,
        onResult: @escaping @MainActor @Sendable (ExerciseResult) -> Void
    ) {
        self.exercise = exercise
        self.audioProvider = audioProvider
        self.audioEnabled = audioEnabled
        self.onResult = onResult

        // Older imported stores can lack the exercise-level relationship even
        // though the lesson still owns all required vocabulary. Falling back
        // to the lesson makes the review work without resetting user data.
        let vocabulary = exercise.vocabulary.isEmpty
            ? (exercise.lesson?.vocabulary ?? [])
            : exercise.vocabulary
        _questions = State(initialValue: Self.makeQuestions(from: vocabulary))
    }

    private var currentQuestion: ReviewQuestion? {
        guard questions.indices.contains(currentQuestionIndex) else { return nil }
        return questions[currentQuestionIndex]
    }

    private var isAnswered: Bool {
        if state == .correct { return true }
        if case .incorrect = state { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TDSpacing.l) {
            ExercisePromptCard(promptText: exercise.promptText)

            if let question = currentQuestion {
                HStack {
                    Spacer()
                    Text(String(localized: "progress.count \(currentQuestionIndex + 1) \(questions.count)"))
                        .font(TDTypography.secondary)
                        .fontWeight(.bold)
                        .foregroundStyle(TDColor.textSecondary)
                }

                wordCard(question)

                VStack(spacing: TDSpacing.s) {
                    ForEach(question.options) { option in
                        ExerciseOptionCard(
                            text: option.text,
                            state: optionState(for: option, question: question),
                            action: { select(option) }
                        )
                    }
                }
            } else {
                TDCard {
                    Text("lessonflow.error.emptyLesson")
                        .font(TDTypography.body)
                        .foregroundStyle(TDColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            Spacer()

            ExerciseFeedbackBanner(state: state)

            if currentQuestion != nil, !isAnswered {
                TDButton(
                    "exercise.button.check",
                    style: selectedKey == nil ? .disabled : .primary
                ) {
                    checkAnswer()
                }
                .accessibilityIdentifier("exercise.check")
            }

            if currentQuestion != nil, isAnswered {
                TDButton("exercise.button.continue") {
                    advanceReview()
                }
                .accessibilityIdentifier("exercise.continue")
            }

            if questions.isEmpty {
                TDButton("exercise.button.continue") {
                    onResult(.correct)
                }
                .accessibilityIdentifier("exercise.continue")
            }
        }
        .padding(TDSpacing.m)
        .background(TDColor.background)
        .onDisappear {
            audioProvider.stopAudio()
        }
    }

    private func wordCard(_ question: ReviewQuestion) -> some View {
        TDCard {
            VStack(spacing: TDSpacing.m) {
                Text(question.targetText)
                    .font(TDTypography.title)
                    .foregroundStyle(TDColor.primary)

                if !question.pronunciation.isEmpty {
                    Text(question.pronunciation)
                        .font(TDTypography.secondary)
                        .foregroundStyle(TDColor.textSecondary)
                }

                Button {
                    guard audioEnabled else { return }
                    audioProvider.playAudio(
                        named: question.audioFileName,
                        fallbackText: question.targetText
                    )
                } label: {
                    Image(systemName: audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(audioEnabled ? TDColor.primary : TDColor.disabledText)
                        .frame(width: 52, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TDPressButtonStyle())
                .disabled(!audioEnabled)
                .accessibilityLabel("exercise.vocabulary.playAudio")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func optionState(
        for option: ReviewOption,
        question: ReviewQuestion
    ) -> ExerciseOptionCard.OptionState {
        switch state {
        case .idle, .answering:
            return option.key == selectedKey ? .selected : .default
        case .correct:
            return option.key == question.key ? .correct : .disabled
        case .incorrect:
            if option.key == selectedKey { return .incorrect }
            if option.key == question.key { return .correct }
            return .disabled
        }
    }

    private func select(_ option: ReviewOption) {
        guard !isAnswered else { return }
        selectedKey = option.key
        state = .answering
    }

    private func checkAnswer() {
        guard let selectedKey, let question = currentQuestion else { return }

        if selectedKey == question.key {
            state = .correct
        } else {
            state = .incorrect(canonicalAnswer: question.correctSourceText)
            if !missedAnswers.contains(question.correctSourceText) {
                missedAnswers.append(question.correctSourceText)
            }
        }
    }

    private func advanceReview() {
        audioProvider.stopAudio()

        if currentQuestionIndex + 1 < questions.count {
            currentQuestionIndex += 1
            selectedKey = nil
            state = .idle
            return
        }

        if missedAnswers.isEmpty {
            onResult(.correct)
        } else {
            onResult(.incorrect(canonicalAnswer: missedAnswers.joined(separator: ", ")))
        }
    }

    private static func makeQuestions(from vocabulary: [VocabularyItem]) -> [ReviewQuestion] {
        let snapshots = vocabulary.map { item in
            (
                key: item.key,
                sourceText: item.sourceText,
                targetText: item.targetText,
                pronunciation: item.pronunciation,
                audioFileName: item.audioFileName ?? ""
            )
        }

        return snapshots.shuffled().map { item in
            let distractors = snapshots
                .filter { $0.key != item.key }
                .shuffled()
                .prefix(3)
                .map { ReviewOption(key: $0.key, text: $0.sourceText) }

            let options = ([ReviewOption(key: item.key, text: item.sourceText)] + distractors)
                .shuffled()

            return ReviewQuestion(
                key: item.key,
                targetText: item.targetText,
                pronunciation: item.pronunciation,
                audioFileName: item.audioFileName,
                correctSourceText: item.sourceText,
                options: options
            )
        }
    }
}
