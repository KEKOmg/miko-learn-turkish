import SwiftUI

/// Bottom tab bar styled with deep teal, large touch targets, and clear
/// active/inactive contrast.
struct TDTabBar: View {
    @Environment(\.tdReduceMotion) private var reduceMotion
    @Binding var selection: AppTab
    let items: [AppTab]

    init(selection: Binding<AppTab>) {
        self._selection = selection
        self.items = AppTab.allCases
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { tab in
                tabItem(for: tab)
            }
        }
        .padding(.top, TDSpacing.s)
        .padding(.bottom, TDSpacing.l)
        .background {
            RoundedRectangle(cornerRadius: TDCornerRadius.button)
                .fill(TDColor.primaryDark)
                .ignoresSafeArea(edges: .bottom)
        }
        .tdShadow(TDShadow.elevated)
    }

    @ViewBuilder
    private func tabItem(for tab: AppTab) -> some View {
        let isActive = selection == tab

        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) {
                selection = tab
            }
        } label: {
            VStack(spacing: TDSpacing.xs) {
                Image(systemName: isActive ? tab.systemImage + ".fill" : tab.systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? .white : TDColor.onDarkMuted)
                Text(tab.titleKey)
                    .font(TDTypography.caption)
                    .fontWeight(isActive ? .bold : .regular)
                    .foregroundStyle(isActive ? .white : TDColor.onDarkMuted)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(Text(tab.titleKey))
        .accessibilityIdentifier("tab.\(tab.accessibilityIdentifier)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
