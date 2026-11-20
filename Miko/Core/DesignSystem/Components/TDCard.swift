import SwiftUI

/// Reusable card surface with a consistent corner radius, shadow, and padding.
struct TDCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let surface: Color
    let content: Content

    init(
        cornerRadius: CGFloat = TDCornerRadius.card,
        padding: CGFloat = TDSpacing.m,
        surface: Color = TDColor.surface,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.surface = surface
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(surface)
            )
            .tdShadow(TDShadow.card)
    }
}

/// A subtle secondary card using the mint / soft surface.
struct TDSecondaryCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(TDSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                    .fill(TDColor.secondarySurface)
            )
    }
}