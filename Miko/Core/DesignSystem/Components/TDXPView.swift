import SwiftUI

/// XP badge — warm gold accent.
struct TDXPView: View {
    let xp: Int

    var body: some View {
        TDStatView(icon: "bolt.fill", value: "\(xp) XP", tint: TDColor.gold)
            .accessibilityLabel(Text(verbatim: "\(xp) XP"))
    }
}
