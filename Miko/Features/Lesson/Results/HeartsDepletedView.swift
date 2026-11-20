import SwiftUI

/// Shown when the user runs out of hearts mid-lesson. Displays the
/// regeneration countdown and offers a way to leave the lesson. No gems,
/// payments, or premium refill — just the timed regeneration path.
struct HeartsDepletedView: View {
    var secondsUntilNextHeart: TimeInterval
    var onLeave: () -> Void

    private var formattedCountdown: String {
        let total = max(0, Int(secondsUntilNextHeart))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: TDSpacing.l) {
            Spacer()

            MascotView(mood: .sad, size: 190)

            Text("hearts.depleted.title")
                .font(TDTypography.title)
                .foregroundStyle(TDColor.textPrimary)

            Text("hearts.depleted.message")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TDSpacing.xl)

            if secondsUntilNextHeart > 0 {
                HStack(spacing: TDSpacing.s) {
                    Image(systemName: "clock")
                        .foregroundStyle(TDColor.primary)
                    Text(String(localized: "hearts.depleted.next \(formattedCountdown)"))
                        .font(TDTypography.cardTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(TDColor.primary)
                }
                .padding(.horizontal, TDSpacing.l)
                .padding(.vertical, TDSpacing.s)
                .background(Capsule().fill(TDColor.secondarySurface))
                .accessibilityIdentifier("hearts.depleted.countdown")
            }

            Spacer()

            TDButton("hearts.depleted.leave", style: .primary, action: onLeave)
                .padding(.horizontal, TDSpacing.m)
                .padding(.bottom, TDSpacing.l)
                .accessibilityIdentifier("hearts.depleted.leave")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TDColor.background)
    }
}
