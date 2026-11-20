import SwiftUI

/// Reusable animated progress bar.
///
/// Supports a 0...1 progress value, an optional tint, and accessibility.
struct TDProgressBar: View {
    @Environment(\.tdReduceMotion) private var reduceMotion
    let progress: Double
    var tint: Color = TDColor.primary
    var track: Color = TDColor.secondarySurface
    var height: CGFloat = 12

    private var clamped: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)

                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: height)
        .animation(
            reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8),
            value: clamped
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("progress.bar.label")
        .accessibilityValue("\(Int(clamped * 100))%")
    }
}
