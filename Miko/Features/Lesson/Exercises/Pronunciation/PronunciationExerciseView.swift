import SwiftUI

struct PronunciationExerciseView: View {
    let exercise: Exercise
    let validator: ExerciseValidating
    let speechProvider: SpeechProviding
    let onResult: @MainActor @Sendable (ExerciseResult) -> Void

    @State private var state: ExerciseState = .idle
    @State private var isRecording: Bool = false
    @State private var recognizedText: String = ""
    @State private var serviceUnavailable: Bool = false

    private var isIncorrect: Bool {
        if case .incorrect = state { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TDSpacing.l) {
            ExercisePromptCard(promptText: exercise.promptText)

            if !exercise.hintKey.isEmpty {
                Text(exercise.hintKey)
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.textSecondary)
            }

            // Text to pronounce
            TDCard {
                Text(exercise.correctAnswerText)
                    .font(TDTypography.title)
                    .foregroundStyle(TDColor.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            // Mic button
            micButton

            if !recognizedText.isEmpty {
                Text(String(localized: "exercise.pronunciation.heard \(recognizedText)"))
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)
            }

            if serviceUnavailable {
                Text("exercise.pronunciation.unavailable")
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.error)
                    .frame(maxWidth: .infinity, alignment: .center)
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

            if serviceUnavailable {
                TDButton("exercise.button.continue") {
                    onResult(.skipped)
                }
                .accessibilityIdentifier("exercise.continue")
            }
        }
        .padding(TDSpacing.m)
        .background(TDColor.background)
        .onDisappear {
            speechProvider.stopRecognition()
        }
    }

    private var micButton: some View {
        Button {
            Task { await startRecording() }
        } label: {
            VStack(spacing: TDSpacing.s) {
                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 48))
                    .foregroundStyle(isRecording ? TDColor.error : TDColor.primary)

                Text(isRecording ? "exercise.pronunciation.recording" : "exercise.pronunciation.tapToSpeak")
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(TDSpacing.xl)
            .background(
                Circle()
                    .fill(TDColor.secondarySurface)
                    .frame(width: 140, height: 140)
            )
        }
        .accessibilityLabel("exercise.pronunciation.tapToSpeak")
        .accessibilityIdentifier("exercise.pronunciation.record")
        .disabled(isRecording || state == .correct || isIncorrect)
    }

    private func startRecording() async {
        guard !isRecording else { return }
        serviceUnavailable = false
        recognizedText = ""
        isRecording = true
        let result = await speechProvider.startRecognition(for: exercise.correctAnswerText)
        isRecording = false

        switch result {
        case .recognized(let text):
            recognizedText = text
            let validationResult = validator.validate(answer: .text(text), exercise: exercise)
            switch validationResult {
            case .correct:
                state = .correct
            case .incorrect(let canonical):
                state = .incorrect(canonicalAnswer: canonical)
            case .skipped:
                // Only the unavailable-speech Continue action produces a skip.
                break
            }
        case .notRecognized:
            state = .incorrect(canonicalAnswer: exercise.correctAnswerText)
        case .unavailable:
            serviceUnavailable = true
            state = .idle
        }
    }

}
