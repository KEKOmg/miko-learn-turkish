import SwiftUI

struct TranslateSentenceExerciseView: View {
    let exercise: Exercise
    let validator: ExerciseValidating
    let onResult: @MainActor @Sendable (ExerciseResult) -> Void

    @State private var userInput: String = ""
    @State private var state: ExerciseState = .idle
    @FocusState private var isInputFocused: Bool

    private var isFinished: Bool {
        state == .correct || isIncorrect
    }

    private var isIncorrect: Bool {
        if case .incorrect = state { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TDSpacing.l) {
            ExercisePromptCard(promptText: exercise.promptText)

            Text("exercise.translateSentence.hint")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)

            TextField("exercise.input.placeholder", text: $userInput, axis: .vertical)
                .font(TDTypography.body)
                .padding(TDSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                        .fill(TDColor.surface)
                )
                .lineLimit(2...4)
                .focused($isInputFocused)
                .submitLabel(.done)
                .onSubmit { checkAnswer() }

            Spacer()

            ExerciseFeedbackBanner(state: state)

            if !isFinished {
                TDButton(
                    "exercise.button.check",
                    style: userInput.trimmingCharacters(in: .whitespaces).isEmpty ? .disabled : .primary
                ) {
                    checkAnswer()
                }
                .accessibilityIdentifier("exercise.check")
            }

            if state == .correct {
                TDButton("exercise.button.continue") {
                    onResult(.correct)
                }
                .accessibilityIdentifier("exercise.continue")
            }

            if isIncorrect, case .incorrect(let canonicalAnswer) = state {
                TDButton("exercise.button.continue") {
                    onResult(.incorrect(canonicalAnswer: canonicalAnswer))
                }
                .accessibilityIdentifier("exercise.continue")
            }
        }
        .padding(TDSpacing.m)
        .background(TDColor.background)
        .onAppear { isInputFocused = true }
    }

    private func checkAnswer() {
        // The user is done typing — drop focus so the keyboard dismisses
        // before the flow advances to the next (possibly non-text) exercise.
        isInputFocused = false
        let result = validator.validate(answer: .text(userInput), exercise: exercise)
        switch result {
        case .correct:
            state = .correct
        case .incorrect(let canonical):
            state = .incorrect(canonicalAnswer: canonical)
        case .skipped:
            // Only the unavailable-speech Continue action produces a skip.
            break
        }
    }

}
