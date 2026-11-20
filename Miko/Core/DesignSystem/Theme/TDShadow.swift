import SwiftUI

/// Centralized shadow definitions so shadows stay consistent across the app.
enum TDShadow {

    /// Default elevation for cards on the background.
    static let card = Shadow(color: Color.black.opacity(0.08), radius: 16, y: 6)

    /// Soft elevation for smaller components (chips, buttons).
    static let soft = Shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)

    /// Slightly stronger elevation for floating / highlighted elements.
    static let elevated = Shadow(color: Color.black.opacity(0.12), radius: 24, y: 10)

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat) {
            self.color = color
            self.radius = radius
            self.x = x
            self.y = y
        }
    }
}

extension View {
    /// Applies a design-system shadow.
    func tdShadow(_ shadow: TDShadow.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
