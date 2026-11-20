import SwiftUI

/// Reusable placeholder for screens whose real implementation belongs to a
/// later phase. Keeps the app shell navigable without fake content.
struct PlaceholderScreen: View {
    let title: LocalizedStringKey
    let systemImage: String
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: TDSpacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(TDColor.primary)

            Text(title)
                .font(TDTypography.title)
                .foregroundStyle(TDColor.textPrimary)

            Text(subtitle)
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(TDSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TDColor.background)
    }
}
