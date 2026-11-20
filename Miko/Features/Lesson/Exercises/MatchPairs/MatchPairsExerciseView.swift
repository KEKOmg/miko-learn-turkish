import SwiftUI

struct MatchPairsBoardLayout: Equatable {
    let sources: [String]
    let targets: [String]

    /// Creates a genuinely mixed board. For three or more pairs it avoids
    /// both same-row answers and the recurring top-left → bottom-right clue.
    static func make(from pairs: [MatchPair]) -> MatchPairsBoardLayout {
        let sources = pairs.map(\.source).shuffled()
        let allTargets = pairs.map(\.target)
        guard pairs.count >= 3 else {
            return MatchPairsBoardLayout(sources: sources, targets: allTargets.shuffled())
        }

        var targetBySource: [String: String] = [:]
        for pair in pairs {
            targetBySource[pair.source] = pair.target
        }
        let expectedTargets = sources.compactMap { targetBySource[$0] }

        for _ in 0..<64 {
            let candidate = allTargets.shuffled()
            let hasSameRowMatch = zip(expectedTargets, candidate).contains { expected, displayed in
                expected == displayed
            }
            let hasCornerShortcut = expectedTargets.first == candidate.last
            if !hasSameRowMatch && !hasCornerShortcut {
                return MatchPairsBoardLayout(sources: sources, targets: candidate)
            }
        }

        // A right cyclic shift is a guaranteed derangement and keeps the
        // first source away from the bottom-right target position.
        let fallback = Array(expectedTargets.suffix(1)) + Array(expectedTargets.dropLast())
        return MatchPairsBoardLayout(sources: sources, targets: fallback)
    }
}

struct MatchPairsExerciseView: View {
    @Environment(\.tdReduceMotion) private var reduceMotion
    private struct MatchedPair: Identifiable, Equatable {
        let source: String
        let target: String

        var id: String { "\(source)\u{001F}\(target)" }
    }

    let exercise: Exercise
    let validator: ExerciseValidating
    let onResult: @MainActor @Sendable (ExerciseResult) -> Void

    @State private var selectedSource: String? = nil
    @State private var selectedTarget: String? = nil
    @State private var matchedPairs: [MatchedPair] = []
    @State private var sourceOrder: [String] = []
    @State private var targetOrder: [String] = []
    @State private var state: ExerciseState = .idle
    @State private var wrongPairFlash: Bool = false

    init(
        exercise: Exercise,
        validator: ExerciseValidating,
        onResult: @escaping @MainActor @Sendable (ExerciseResult) -> Void
    ) {
        self.exercise = exercise
        self.validator = validator
        self.onResult = onResult

        let payload = ExerciseFactory.decodePayload(MatchPairsPayload.self, from: exercise)
        let layout = MatchPairsBoardLayout.make(from: payload?.pairs ?? [])
        _sourceOrder = State(initialValue: layout.sources)
        _targetOrder = State(initialValue: layout.targets)
    }

    private var isIncorrect: Bool {
        if case .incorrect = state { return true }
        return false
    }

    private var payload: MatchPairsPayload? {
        ExerciseFactory.decodePayload(MatchPairsPayload.self, from: exercise)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TDSpacing.l) {
            ExercisePromptCard(promptText: exercise.promptText)

            if payload != nil {
                if !matchedPairs.isEmpty {
                    VStack(spacing: TDSpacing.s) {
                        ForEach(matchedPairs) { pair in
                            matchedPairRow(pair)
                        }
                    }

                    Divider()
                }

                HStack(alignment: .top, spacing: TDSpacing.m) {
                    // Source column
                    VStack(spacing: TDSpacing.s) {
                        ForEach(unmatchedSources, id: \.self) { source in
                            pairCard(source, isSource: true)
                        }
                    }

                    // Target column
                    VStack(spacing: TDSpacing.s) {
                        ForEach(unmatchedTargets, id: \.self) { target in
                            pairCard(target, isSource: false)
                        }
                    }
                }
            }

            Spacer()

            ExerciseFeedbackBanner(state: state)

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

    private var unmatchedSources: [String] {
        sourceOrder.filter { source in
            !matchedPairs.contains(where: { $0.source == source })
        }
    }

    private var unmatchedTargets: [String] {
        targetOrder.filter { target in
            !matchedPairs.contains(where: { $0.target == target })
        }
    }

    private func matchedPairRow(_ pair: MatchedPair) -> some View {
        HStack(spacing: TDSpacing.s) {
            matchedCard(pair.source)

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(TDColor.success)
                .accessibilityHidden(true)

            matchedCard(pair.target)
        }
        .accessibilityElement(children: .combine)
    }

    private func matchedCard(_ text: String) -> some View {
        Text(text)
            .font(TDTypography.body)
            .foregroundStyle(TDColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                    .fill(TDColor.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                    .stroke(TDColor.success, lineWidth: 2)
            )
    }

    private func pairCard(_ text: String, isSource: Bool) -> some View {
        let isSelected = isSource ? selectedSource == text : selectedTarget == text
        let selectionColor = wrongPairFlash && isSelected ? TDColor.coral : TDColor.primary

        return Button {
            selectPair(text: text, isSource: isSource)
        } label: {
            Text(text)
                .font(TDTypography.body)
                .foregroundStyle(TDColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                        .fill(isSelected ? TDColor.secondarySurface : TDColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                        .stroke(isSelected ? selectionColor : Color.clear, lineWidth: 2)
                )
        }
        .accessibilityValue(isSelected ? "selected" : "unselected")
    }

    private func selectPair(text: String, isSource: Bool) {
        guard state == .idle || state == .answering else { return }

        if isSource {
            selectedSource = (selectedSource == text) ? nil : text
        } else {
            selectedTarget = (selectedTarget == text) ? nil : text
        }

        if let source = selectedSource, let target = selectedTarget {
            tryMatch(source: source, target: target)
        }
    }

    private func tryMatch(source: String, target: String) {
        // Match pairs are validated incrementally (one pair at a time) against
        // the decoded payload. The `MatchPairsValidator` validates the
        // *complete* set, which is the contract covered by unit tests; here we
        // only need to know whether this single (source, target) pairing is
        // correct.
        guard let payload else { return }
        let isCorrect = payload.pairs.contains { pair in
            TurkishTextNormalizer.normalize(pair.source) == TurkishTextNormalizer.normalize(source)
            && TurkishTextNormalizer.normalize(pair.target) == TurkishTextNormalizer.normalize(target)
        }

        if isCorrect {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                matchedPairs.append(MatchedPair(source: source, target: target))
            }
            selectedSource = nil
            selectedTarget = nil
            state = .answering

            if matchedPairs.count == payload.pairs.count {
                state = .correct
            }
        } else {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                wrongPairFlash = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                selectedSource = nil
                selectedTarget = nil
                wrongPairFlash = false
            }
        }
    }

}
