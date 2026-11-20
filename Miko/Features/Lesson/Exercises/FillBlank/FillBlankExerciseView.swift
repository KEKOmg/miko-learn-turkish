import SwiftUI

struct FillBlankExerciseView: View {
    let exercise: Exercise
    let validator: ExerciseValidating
    let onResult: @MainActor @Sendable (ExerciseResult) -> Void

    @State private var selectedOption: String? = nil
    @State private var state: ExerciseState = .idle
    @State private var optionOrder: [String]

    init(
        exercise: Exercise,
        validator: ExerciseValidating,
        onResult: @escaping @MainActor @Sendable (ExerciseResult) -> Void
    ) {
        self.exercise = exercise
        self.validator = validator
        self.onResult = onResult

        let payload = ExerciseFactory.decodePayload(FillBlankPayload.self, from: exercise)
        _optionOrder = State(initialValue: (payload?.options ?? []).shuffled())
    }

    private var isFinished: Bool {
        state == .correct || isIncorrect
    }

    private var isIncorrect: Bool {
        if case .incorrect = state { return true }
        return false
    }

    private var payload: FillBlankPayload? {
        ExerciseFactory.decodePayload(FillBlankPayload.self, from: exercise)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TDSpacing.l) {
            if let payload {
                ExercisePromptCard(promptText: exercise.promptText)

                // Sentence with blank
                sentenceWithBlank(payload: payload)

                // Options
                VStack(spacing: TDSpacing.s) {
                    ForEach(optionOrder, id: \.self) { option in
                        ExerciseOptionCard(
                            text: option,
                            state: optionState(for: option, payload: payload),
                            action: { selectOption(option) }
                        )
                    }
                }
            }

            Spacer()

            ExerciseFeedbackBanner(state: state)

            if !isFinished {
                TDButton(
                    "exercise.button.check",
                    style: selectedOption == nil ? .disabled : .primary
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
    }

    private func sentenceWithBlank(payload: FillBlankPayload) -> some View {
        // Tolerant parsing: any run of 3+ underscores is treated as the blank,
        // so a template authored with a different run length still renders a
        // blank slot rather than literal underscores.
        let parts = FillBlankPayload.split(template: payload.template)
        let blankText = selectedOption ?? FillBlankPayload.canonicalPlaceholder

        return TDCard {
            HStack(spacing: TDSpacing.xs) {
                if let parts, !parts.prefix.isEmpty {
                    Text(parts.prefix)
                        .font(TDTypography.body)
                        .foregroundStyle(TDColor.textPrimary)
                }
                Text(blankText)
                    .font(TDTypography.body)
                    .fontWeight(.bold)
                    .foregroundStyle(blankTextColor)
                    .padding(.horizontal, TDSpacing.s)
                    .padding(.vertical, TDSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: TDCornerRadius.small)
                            .fill(TDColor.secondarySurface)
                    )
                if let parts, !parts.suffix.isEmpty {
                    Text(parts.suffix)
                        .font(TDTypography.body)
                        .foregroundStyle(TDColor.textPrimary)
                }
                // No placeholder found — show the raw template after the blank
                // so the sentence is still readable.
                if parts == nil {
                    Text(payload.template)
                        .font(TDTypography.body)
                        .foregroundStyle(TDColor.textPrimary)
                }
            }
        }
    }

    private var blankTextColor: Color {
        switch state {
        case .correct: return TDColor.success
        case .incorrect: return TDColor.error
        default: return TDColor.primary
        }
    }

    private func optionState(for option: String, payload: FillBlankPayload) -> ExerciseOptionCard.OptionState {
        switch state {
        case .idle, .answering:
            return option == selectedOption ? .selected : .default
        case .correct:
            return option == payload.blank ? .correct : .disabled
        case .incorrect:
            if option == selectedOption {
                return .incorrect
            }
            if option == payload.blank {
                return .correct
            }
            return .disabled
        }
    }

    private func selectOption(_ option: String) {
        guard state == .idle || state == .answering else { return }
        selectedOption = option
        state = .answering
    }

    private func checkAnswer() {
        guard let selectedOption else { return }
        let result = validator.validate(answer: .text(selectedOption), exercise: exercise)
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
