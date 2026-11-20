import SwiftUI

/// Development-only preview screen demonstrating the complete design system.
/// This is not the real Home screen — it exists to verify the visual language.
struct DesignSystemPreview: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TDSpacing.xl) {
                    header
                    colorsSection
                    typographySection
                    buttonsSection
                    cardsSection
                    progressSection
                    gamificationSection
                    statesSection
                    localizationSection
                }
                .padding(TDSpacing.m)
            }
            .background(TDColor.background)
            .safeAreaPadding(.bottom, TDSpacing.m)

            TDTabBar(selection: $selectedTab)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: TDSpacing.xs) {
            Text("design.preview.title")
                .font(TDTypography.largeTitle)
                .foregroundStyle(TDColor.textPrimary)
            Text("design.preview.subtitle")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
        }
    }

    private var colorsSection: some View {
        section(title: "design.preview.colors") {
            VStack(spacing: TDSpacing.m) {
                paletteRow(title: "design.color.tealDark", color: TDColor.tealDark)
                paletteRow(title: "design.color.teal", color: TDColor.teal)
                paletteRow(title: "design.color.coral", color: TDColor.coral)
                paletteRow(title: "design.color.cream", color: TDColor.cream)
                paletteRow(title: "design.color.mint", color: TDColor.mint)
                paletteRow(title: "design.color.gold", color: TDColor.gold)
            }
        }
    }

    private func paletteRow(title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: TDSpacing.m) {
            RoundedRectangle(cornerRadius: TDCornerRadius.small)
                .fill(color)
                .frame(width: 44, height: 44)
            Text(title)
                .font(TDTypography.body)
                .foregroundStyle(TDColor.textPrimary)
        }
    }

    private var typographySection: some View {
        section(title: "design.preview.typography") {
            VStack(alignment: .leading, spacing: TDSpacing.m) {
                Text("design.typography.largeTitle").font(TDTypography.largeTitle)
                Text("design.typography.title").font(TDTypography.title)
                Text("design.typography.sectionTitle").font(TDTypography.sectionTitle)
                Text("design.typography.cardTitle").font(TDTypography.cardTitle)
                Text("design.typography.body").font(TDTypography.body)
                Text("design.typography.secondary").font(TDTypography.secondary)
                Text("design.typography.button").font(TDTypography.button)
                Text("design.typography.caption").font(TDTypography.caption)
            }
            .foregroundStyle(TDColor.textPrimary)
        }
    }

    private var buttonsSection: some View {
        section(title: "design.preview.buttons") {
            VStack(spacing: TDSpacing.m) {
                TDButton("design.button.primary") {}
                TDButton("design.button.primaryCompact", style: .primaryCompact) {}
                TDButton("design.button.secondary", style: .secondary) {}
                TDButton("design.button.destructive", style: .destructive) {}
                TDButton("design.button.disabled", style: .disabled) {}
            }
        }
    }

    private var cardsSection: some View {
        section(title: "design.preview.cards") {
            VStack(spacing: TDSpacing.m) {
                TDCard {
                    VStack(alignment: .leading, spacing: TDSpacing.s) {
                        Text("design.card.title").font(TDTypography.cardTitle)
                        Text("design.card.body").font(TDTypography.secondary)
                    }
                }

                TDSecondaryCard {
                    Text("design.card.secondary")
                        .font(TDTypography.body)
                }
            }
        }
    }

    private var progressSection: some View {
        section(title: "design.preview.progress") {
            VStack(spacing: TDSpacing.m) {
                TDProgressBar(progress: 0.25)
                TDProgressBar(progress: 0.5)
                TDProgressBar(progress: 0.75, tint: TDColor.gold)
                TDProgressBar(progress: 1.0)
            }
        }
    }

    private var gamificationSection: some View {
        section(title: "design.preview.gamification") {
            VStack(alignment: .leading, spacing: TDSpacing.m) {
                HStack(spacing: TDSpacing.s) {
                    TDXPView(xp: 125)
                    TDHeartView(total: 5, remaining: 3)
                    TDStreakView(days: 7)
                }
                HStack(spacing: TDSpacing.m) {
                    TDAchievementBadge(icon: "star.fill")
                    TDAchievementBadge(icon: "crown.fill")
                    TDAchievementBadge(icon: "flame.fill")
                    TDAchievementBadge(icon: "trophy.fill", earned: false)
                }
            }
        }
    }

    private var statesSection: some View {
        section(title: "design.preview.states") {
            VStack(spacing: TDSpacing.m) {
                stateRow(title: "design.state.normal", color: TDColor.primary)
                stateRow(title: "design.state.selected", color: TDColor.tealDark)
                stateRow(title: "design.state.success", color: TDColor.success)
                stateRow(title: "design.state.error", color: TDColor.error)
                stateRow(title: "design.state.disabled", color: TDColor.disabled)
            }
        }
    }

    private func stateRow(title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: TDSpacing.m) {
            Circle().fill(color).frame(width: 16, height: 16)
            Text(title).font(TDTypography.body)
                .foregroundStyle(TDColor.textPrimary)
        }
    }

    private var localizationSection: some View {
        section(title: "design.preview.localization") {
            VStack(alignment: .leading, spacing: TDSpacing.s) {
                Text("localization.greeting").font(TDTypography.body)
                Text("localization.items 1").font(TDTypography.secondary)
                Text("localization.items 2").font(TDTypography.secondary)
                Text("localization.items 5").font(TDTypography.secondary)
            }
            .foregroundStyle(TDColor.textPrimary)
        }
    }

    private func section<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: TDSpacing.m) {
            Text(title)
                .font(TDTypography.sectionTitle)
                .foregroundStyle(TDColor.textPrimary)
            content()
        }
    }
}

#Preview {
    DesignSystemPreview()
}
