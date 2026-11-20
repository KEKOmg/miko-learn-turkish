import SwiftUI

struct MultipleChoiceExerciseView: View {
    let exercise: Exercise
    let validator: ExerciseValidating
    let onResult: @MainActor @Sendable (ExerciseResult) -> Void

    @State private var selectedIndex: Int? = nil
    @State private var state: ExerciseState = .idle
    @State private var optionOrder: [Int]

    init(
        exercise: Exercise,
        validator: ExerciseValidating,
        onResult: @escaping @MainActor @Sendable (ExerciseResult) -> Void
    ) {
        self.exercise = exercise
        self.validator = validator
        self.onResult = onResult

        let payload = ExerciseFactory.decodePayload(MultipleChoicePayload.self, from: exercise)
        _optionOrder = State(initialValue: Array(payload?.options.indices ?? 0..<0).shuffled())
    }

    private var isFinished: Bool {
        state == .correct || isIncorrect
    }

    private var isIncorrect: Bool {
        if case .incorrect = state { return true }
        return false
    }

    private var payload: MultipleChoicePayload? {
        ExerciseFactory.decodePayload(MultipleChoicePayload.self, from: exercise)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TDSpacing.l) {
            ExercisePromptCard(promptText: exercise.promptText)

            if let payload {
                VStack(spacing: TDSpacing.s) {
                    ForEach(optionOrder, id: \.self) { index in
                        ExerciseOptionCard(
                            text: payload.options[index],
                            state: optionState(for: index, payload: payload),
                            action: { selectOption(index) }
                        )
                    }
                }
            }

            Spacer()

            ExerciseFeedbackBanner(state: state)

            if !isFinished {
                TDButton(
                    "exercise.button.check",
                    style: selectedIndex == nil ? .disabled : .primary
                ) {
                    checkAnswer()
                }
                .accessibilityIdentifier("exercise.check")
            }

            if state == .correct {
                TDButton("exercise.button.continue", style: .primary) {
                    onResult(.correct)
                }
                .accessibilityIdentifier("exercise.continue")
            }

            if isIncorrect, case .incorrect(let canonicalAnswer) = state {
                TDButton("exercise.button.continue", style: .primary) {
                    onResult(.incorrect(canonicalAnswer: canonicalAnswer))
                }
                .accessibilityIdentifier("exercise.continue")
            }
        }
        .padding(TDSpacing.m)
        .background(TDColor.background)
    }

    private func optionState(for index: Int, payload: MultipleChoicePayload) -> ExerciseOptionCard.OptionState {
        switch state {
        case .idle, .answering:
            if index == selectedIndex {
                return .selected
            }
            return .default
        case .correct:
            if index == payload.correctIndex {
                return .correct
            }
            return .disabled
        case .incorrect:
            if index == selectedIndex {
                return .incorrect
            }
            if index == payload.correctIndex {
                return .correct
            }
            return .disabled
        }
    }

    private func selectOption(_ index: Int) {
        guard state == .idle || state == .answering else { return }
        selectedIndex = index
        state = .answering
    }

    private func checkAnswer() {
        guard let selectedIndex else { return }
        let result = validator.validate(answer: .index(selectedIndex), exercise: exercise)
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
