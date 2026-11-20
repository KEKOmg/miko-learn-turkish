import SwiftUI

/// The interaction state of an exercise.
enum ExerciseState: Equatable {
    case idle
    case answering
    case correct
    case incorrect(canonicalAnswer: String)
}

/// A banner that shows success or failure feedback using both color
/// AND icon + text, so it does not rely on color alone.
struct ExerciseFeedbackBanner: View {
    let state: ExerciseState

    var body: some View {
        switch state {
        case .correct:
            feedbackCard(
                title: "exercise.feedback.correct",
                icon: "checkmark.circle.fill",
                color: TDColor.success,
                mood: .cheer
            )
        case .incorrect(let canonical):
            feedbackCard(
                title: "exercise.feedback.incorrect",
                icon: "xmark.circle.fill",
                color: TDColor.error,
                mood: .wrong,
                canonicalAnswer: canonical
            )
        case .idle, .answering:
            EmptyView()
        }
    }

    private func feedbackCard(
        title: LocalizedStringKey,
        icon: String,
        color: Color,
        mood: MascotView.Mood,
        canonicalAnswer: String = ""
    ) -> some View {
        HStack(alignment: .center, spacing: TDSpacing.m) {
            MascotView(mood: mood, size: 84)

            VStack(alignment: .leading, spacing: TDSpacing.xs) {
                HStack(spacing: TDSpacing.s) {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(TDTypography.cardTitle)
                        .foregroundStyle(color)
                }

                if !canonicalAnswer.isEmpty {
                    Text(String(localized: "exercise.feedback.correctAnswer \(canonicalAnswer)"))
                        .font(TDTypography.secondary)
                        .foregroundStyle(TDColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(TDSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                .fill(color.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
    }
}

/// Displays the exercise prompt text in a styled card.
struct ExercisePromptCard: View {
    let promptText: String

    var body: some View {
        TDCard {
            Text(promptText)
                .font(TDTypography.title)
                .foregroundStyle(TDColor.textPrimary)
                .multilineTextAlignment(.leading)
        }
    }
}

/// A large selectable option card for multiple-choice-style exercises.
struct ExerciseOptionCard: View {
    let text: String
    let state: OptionState
    let action: () -> Void

    enum OptionState {
        case `default`
        case selected
        case correct
        case incorrect
        case disabled

        var backgroundColor: Color {
            switch self {
            case .default:   return TDColor.surface
            case .selected:  return TDColor.secondarySurface
            case .correct:   return TDColor.success.opacity(0.2)
            case .incorrect: return TDColor.error.opacity(0.2)
            case .disabled:  return TDColor.disabled
            }
        }

        var borderColor: Color {
            switch self {
            case .default:   return Color.clear
            case .selected:  return TDColor.primary
            case .correct:   return TDColor.success
            case .incorrect: return TDColor.error
            case .disabled:  return Color.clear
            }
        }

        var textColor: Color {
            switch self {
            case .default:   return TDColor.textPrimary
            case .selected:  return TDColor.primary
            case .correct:   return TDColor.success
            case .incorrect: return TDColor.error
            case .disabled:  return TDColor.disabledText
            }
        }

        var icon: String? {
            switch self {
            case .correct:   return "checkmark.circle.fill"
            case .incorrect: return "xmark.circle.fill"
            default:         return nil
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(TDTypography.body)
                    .foregroundStyle(state.textColor)
                Spacer()
                if let icon = state.icon {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(state.textColor)
                }
            }
            .padding(.horizontal, TDSpacing.m)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                    .fill(state.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                    .stroke(state.borderColor, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TDPressButtonStyle())
        .disabled(state == .disabled)
    }
}
