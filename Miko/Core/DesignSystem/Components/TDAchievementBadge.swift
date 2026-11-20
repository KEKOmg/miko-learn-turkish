import SwiftUI

/// Achievement / reward badge — gold + soft mint.
struct TDAchievementBadge: View {
    let icon: String
    var earned: Bool = true
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .fill(earned ? TDColor.gold.opacity(0.25) : TDColor.secondarySurface)
                .frame(width: size, height: size)

            Circle()
                .stroke(earned ? TDColor.gold : TDColor.disabled, lineWidth: 3)
                .frame(width: size, height: size)

            Image(systemName: earned ? icon : "lock.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(earned ? TDColor.textPrimary : TDColor.disabledText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(earned ? Text("a11y.achievement.earned") : Text("a11y.achievement.locked"))
    }
}
