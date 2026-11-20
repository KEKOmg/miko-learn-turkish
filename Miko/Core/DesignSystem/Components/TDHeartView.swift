import SwiftUI

/// Hearts / lives display — coral red accent.
struct TDHeartView: View {
    let total: Int
    let remaining: Int

    var body: some View {
        HStack(spacing: TDSpacing.s) {
            Image(systemName: "heart.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TDColor.coral)
            Text(String(localized: "progress.count \(remaining) \(total)"))
                .font(TDTypography.secondary)
                .fontWeight(.bold)
                .foregroundStyle(TDColor.coral)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, TDSpacing.m)
        .padding(.vertical, TDSpacing.s)
        .background(Capsule().fill(TDColor.secondarySurface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("hearts.value")
        .accessibilityValue(String(localized: "progress.count \(remaining) \(total)"))
    }
}
