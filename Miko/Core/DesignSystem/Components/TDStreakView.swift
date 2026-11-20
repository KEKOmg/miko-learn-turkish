import SwiftUI

/// Streak display — flame icon with coral/gold combination.
struct TDStreakView: View {
    let days: Int

    var body: some View {
        HStack(spacing: TDSpacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TDColor.coral)
            Text("\(days)")
                .font(TDTypography.secondary)
                .fontWeight(.bold)
                .foregroundStyle(TDColor.textPrimary)
        }
        .padding(.horizontal, TDSpacing.m)
        .padding(.vertical, TDSpacing.s)
        .background(Capsule().fill(TDColor.secondarySurface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("streak.value")
        .accessibilityValue("\(days)")
    }
}
