import SwiftUI

/// End-of-lesson summary. XP is a temporary calculated value — Phase 5
/// (gamification service) will replace `outcome.xpEarned` without changing
/// this screen's structure.
struct LessonResultsView: View {
    @Environment(\.tdReduceMotion) private var reduceMotion
    let outcome: LessonFlowViewModel.LessonOutcome
    let showsPersistenceWarning: Bool
    var onDone: () -> Void

    @State private var appeared = false

    private var starCount: Int {
        if outcome.accuracy >= 0.9 { return 3 }
        if outcome.accuracy >= 0.6 { return 2 }
        return 1
    }

    var body: some View {
        VStack(spacing: TDSpacing.l) {
            Spacer()

            MascotView(mood: .cheer, size: 128)
                .scaleEffect(appeared ? 1 : 0.65)
                .opacity(appeared ? 1 : 0)

            starsView
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)

            Text(outcome.isPractice
                 ? "results.practice"
                 : "results.congratulations")
                .font(TDTypography.title)
                .foregroundStyle(TDColor.textPrimary)
                .accessibilityIdentifier("lessonResults.root")

            Text(outcome.lessonTitle)
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)

            TDCard {
                VStack(spacing: TDSpacing.m) {
                    statRow(
                        icon: "target",
                        label: "results.accuracy",
                        value: "\(Int((outcome.accuracy * 100).rounded()))%"
                    )
                    statRow(
                        icon: "checkmark.circle",
                        label: "results.correct",
                        value: String(localized: "results.correctValue \(outcome.correctCount) \(outcome.totalCount)")
                    )
                    statRow(
                        icon: "bolt.fill",
                        label: "results.xp",
                        value: "+\(outcome.xpEarned)"
                    )
                }
            }
            .padding(.horizontal, TDSpacing.l)

            if showsPersistenceWarning {
                Label("results.persistenceWarning", systemImage: "exclamationmark.triangle")
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.warning)
                    .padding(.horizontal, TDSpacing.l)
            }

            Spacer()

            TDButton("results.done", style: .primary, action: onDone)
                .accessibilityIdentifier("lessonResults.done")
                .padding(.horizontal, TDSpacing.m)
                .padding(.bottom, TDSpacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TDColor.background)
        .onAppear {
            withAnimation(
                reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6).delay(0.1)
            ) {
                appeared = true
            }
        }
    }

    private var starsView: some View {
        HStack(spacing: TDSpacing.s) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(index < starCount ? TDColor.gold : TDColor.disabled)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("results.stars")
        .accessibilityValue("\(starCount) / 3")
    }

    private func statRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(TDTypography.cardTitle)
                .foregroundStyle(TDColor.textSecondary)
            Spacer()
            Text(value)
                .font(TDTypography.cardTitle)
                .fontWeight(.bold)
                .foregroundStyle(TDColor.textPrimary)
        }
    }
}
