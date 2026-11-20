import SwiftUI

struct BuildSentenceExerciseView: View {
    let exercise: Exercise
    let validator: ExerciseValidating
    let onResult: @MainActor @Sendable (ExerciseResult) -> Void

    @State private var selectedWords: [String] = []
    @State private var state: ExerciseState = .idle
    @State private var wordBank: [String]

    init(
        exercise: Exercise,
        validator: ExerciseValidating,
        onResult: @escaping @MainActor @Sendable (ExerciseResult) -> Void
    ) {
        self.exercise = exercise
        self.validator = validator
        self.onResult = onResult

        let payload = ExerciseFactory.decodePayload(BuildSentencePayload.self, from: exercise)
        _wordBank = State(initialValue: (payload?.wordBank ?? []).shuffled())
    }

    private var isFinished: Bool {
        state == .correct || isIncorrect
    }

    private var isIncorrect: Bool {
        if case .incorrect = state { return true }
        return false
    }

    private var payload: BuildSentencePayload? {
        ExerciseFactory.decodePayload(BuildSentencePayload.self, from: exercise)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TDSpacing.l) {
            ExercisePromptCard(promptText: exercise.promptText)

            // Selected words area
            TDCard {
                FlowLayout(spacing: TDSpacing.s) {
                    ForEach(selectedWords.indices, id: \.self) { index in
                        wordChip(selectedWords[index], isUsed: true) {
                            removeWord(at: index)
                        }
                    }
                    if selectedWords.isEmpty {
                        Text("exercise.buildSentence.empty")
                            .font(TDTypography.secondary)
                            .foregroundStyle(TDColor.textSecondary)
                    }
                }
            }

            // Word bank
            if let payload {
                FlowLayout(spacing: TDSpacing.s) {
                    ForEach(wordBank.indices, id: \.self) { index in
                        let word = wordBank[index]
                        wordChip(word, isUsed: false) {
                            addWord(word)
                        }
                        .opacity(isWordUsed(word, payload: payload) ? 0.3 : 1.0)
                    }
                }
            }

            Spacer()

            ExerciseFeedbackBanner(state: state)

            if !isFinished {
                TDButton(
                    "exercise.button.check",
                    style: selectedWords.isEmpty ? .disabled : .primary
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

    private func isWordUsed(_ word: String, payload: BuildSentencePayload) -> Bool {
        let usedCount = selectedWords.filter { $0 == word }.count
        let bankCount = payload.wordBank.filter { $0 == word }.count
        return usedCount >= bankCount
    }

    private func wordChip(_ word: String, isUsed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word)
                .font(TDTypography.body)
                .foregroundStyle(TDColor.textPrimary)
                .padding(.horizontal, TDSpacing.m)
                .padding(.vertical, TDSpacing.s)
                .background(
                    RoundedRectangle(cornerRadius: TDCornerRadius.small)
                        .fill(TDColor.secondarySurface)
                )
        }
    }

    private func addWord(_ word: String) {
        guard state == .idle || state == .answering else { return }
        selectedWords.append(word)
        state = .answering
    }

    private func removeWord(at index: Int) {
        guard state == .idle || state == .answering else { return }
        guard selectedWords.indices.contains(index) else { return }
        selectedWords.remove(at: index)
    }

    private func checkAnswer() {
        let result = validator.validate(answer: .wordOrder(selectedWords), exercise: exercise)
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

/// Simple flow layout for word chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                height += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
