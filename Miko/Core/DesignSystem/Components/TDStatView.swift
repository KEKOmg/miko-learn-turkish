import SwiftUI

/// Base pill-shaped stat display (e.g. "50 XP", "3 ❤️", "🔥 7").
///
/// A small reusable chip used by the gamification components below.
struct TDStatView: View {
    let icon: String
    let value: String
    var tint: Color = TDColor.gold
    var filled: Bool = true

    var body: some View {
        HStack(spacing: TDSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
            Text(value)
                .font(TDTypography.secondary)
                .fontWeight(.semibold)
        }
        .foregroundStyle(filled ? .white : tint)
        .padding(.horizontal, TDSpacing.m)
        .padding(.vertical, TDSpacing.s)
        .background(
            Capsule().fill(filled ? tint : TDColor.secondarySurface)
        )
        .tdShadow(TDShadow.soft)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("a11y.stat.label"))
        .accessibilityValue(Text(value))
    }
}
