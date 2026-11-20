import SwiftUI

struct ListeningExerciseView: View {
    @Environment(\.tdReduceMotion) private var reduceMotion

    let exercise: Exercise
    let validator: ExerciseValidating
    let audioProvider: AudioProviding
    let audioEnabled: Bool
    let onResult: @MainActor @Sendable (ExerciseResult) -> Void

    @State private var selectedIndex: Int? = nil
    @State private var state: ExerciseState = .idle
    @State private var isPlaying: Bool = false
    @State private var hasAutoPlayed: Bool = false
    @State private var optionOrder: [Int]

    init(
        exercise: Exercise,
        validator: ExerciseValidating,
        audioProvider: AudioProviding,
        audioEnabled: Bool,
        onResult: @escaping @MainActor @Sendable (ExerciseResult) -> Void
    ) {
        self.exercise = exercise
        self.validator = validator
        self.audioProvider = audioProvider
        self.audioEnabled = audioEnabled
        self.onResult = onResult

        let payload = ExerciseFactory.decodePayload(ListeningComprehensionPayload.self, from: exercise)
        _optionOrder = State(initialValue: Array(payload?.options.indices ?? 0..<0).shuffled())
    }

    private var isFinished: Bool {
        state == .correct || isIncorrect
    }

    private var isIncorrect: Bool {
        if case .incorrect = state { return true }
        return false
    }

    private var payload: ListeningComprehensionPayload? {
        ExerciseFactory.decodePayload(ListeningComprehensionPayload.self, from: exercise)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TDSpacing.l) {
            ExercisePromptCard(promptText: exercise.promptText)

            // Large audio button
            audioButton

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
        .task {
            guard !hasAutoPlayed else { return }
            hasAutoPlayed = true
            playAudio()
        }
        .onDisappear {
            audioProvider.stopAudio()
        }
    }

    private var audioButton: some View {
        Button {
            playAudio()
        } label: {
            VStack(spacing: TDSpacing.s) {
                MascotView(mood: .listening, size: 190)
                    .scaleEffect(isPlaying && !reduceMotion ? 1.04 : 1)

                Label(
                    "exercise.listening.play",
                    systemImage: audioEnabled
                        ? (isPlaying ? "speaker.wave.3.fill" : "speaker.fill")
                        : "speaker.slash.fill"
                )
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(audioEnabled ? TDColor.primary : TDColor.disabledText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TDSpacing.m)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: TDCornerRadius.card)
                    .fill(TDColor.secondarySurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: TDCornerRadius.card)
                    .stroke(isPlaying ? TDColor.primary : Color.clear, lineWidth: 2)
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72),
                value: isPlaying
            )
        }
        .buttonStyle(TDPressButtonStyle())
        .disabled(!audioEnabled)
        .opacity(audioEnabled ? 1 : 0.65)
        .accessibilityLabel("exercise.listening.playAudio")
        .accessibilityIdentifier("exercise.listening.playAudio")
    }

    private func optionState(for index: Int, payload: ListeningComprehensionPayload) -> ExerciseOptionCard.OptionState {
        switch state {
        case .idle, .answering:
            return index == selectedIndex ? .selected : .default
        case .correct:
            return index == payload.correctIndex ? .correct : .disabled
        case .incorrect:
            if index == selectedIndex {
                return .incorrect
            }
            return .disabled
        }
    }

    private func selectOption(_ index: Int) {
        guard state == .idle || state == .answering else { return }
        selectedIndex = index
        state = .answering
    }

    private func playAudio() {
        guard audioEnabled else { return }
        guard let payload else { return }
        isPlaying = true
        audioProvider.playAudio(named: payload.audioFileName, fallbackText: payload.transcript)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isPlaying = audioProvider.isPlaying
            if isPlaying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    isPlaying = false
                }
            }
        }
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
