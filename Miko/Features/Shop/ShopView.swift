import SwiftUI
import SwiftData

/// Shop screen.
///
/// Shows the user's gems and hearts balance and offers a one-tap "refill
/// hearts" purchase for a fixed gem cost. All data and mutations flow
/// through `ShopViewModel`; the view never touches SwiftData directly.
struct ShopView: View {
    var isActive: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appContainer) private var appContainer
    @Environment(AppState.self) private var appState

    @State private var viewModel: ShopViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: TDSpacing.l) {
                if let viewModel, let snapshot = viewModel.snapshot {
                    content(viewModel: viewModel, snapshot: snapshot)
                } else {
                    loadingView
                }
            }
            .padding(.horizontal, TDSpacing.l)
            .padding(.top, TDSpacing.l)
            .padding(.bottom, TDSpacing.xxl)
        }
        .background(TDColor.background)
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("shop.root")
                .allowsHitTesting(false)
        }
        .task(id: isActive) {
            guard isActive else { return }
            if viewModel == nil {
                let vm = ShopViewModel(
                    lessonProgressRepository: appContainer?.lessonProgressRepository
                        ?? LessonProgressRepository(
                            context: modelContext,
                            profileID: appState.activeProfileID
                        ),
                    heartsRepository: appContainer?.heartsRepository,
                    gamificationRepository: appContainer?.gamificationRepository
                )
                viewModel = vm
                vm.load()
            } else {
                viewModel?.load()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(viewModel: ShopViewModel, snapshot: ShopViewModel.Snapshot) -> some View {
        header
        balanceCard(snapshot: snapshot)
        refillCard(viewModel: viewModel, snapshot: snapshot)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TDSpacing.xs) {
            Text("screen.shop.title")
                .font(TDTypography.largeTitle)
                .foregroundStyle(TDColor.screenTitle)
                .accessibilityIdentifier("shop.header")
            Text("screen.shop.subtitle")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func balanceCard(snapshot: ShopViewModel.Snapshot) -> some View {
        TDCard {
            VStack(alignment: .leading, spacing: TDSpacing.m) {
                Text("shop.section.balance")
                    .font(TDTypography.sectionTitle)
                    .foregroundStyle(TDColor.textPrimary)

                HStack(spacing: TDSpacing.l) {
                    balanceTile(
                        icon: "diamond.fill",
                        label: "shop.gems.label",
                        value: "\(snapshot.gems)",
                        tint: TDColor.gold,
                        identifier: "shop.gems"
                    )
                    balanceTile(
                        icon: "heart.fill",
                        label: "shop.hearts.label",
                        value: "\(snapshot.heartsRemaining)/\(snapshot.heartsTotal)",
                        tint: TDColor.coral,
                        identifier: "shop.hearts"
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shop.balance")
    }

    private func balanceTile(
        icon: String,
        label: LocalizedStringKey,
        value: String,
        tint: Color,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: TDSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(TDTypography.cardTitle)
                .fontWeight(.bold)
                .foregroundStyle(TDColor.textPrimary)
            Text(label)
                .font(TDTypography.caption)
                .foregroundStyle(TDColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func refillCard(
        viewModel: ShopViewModel,
        snapshot: ShopViewModel.Snapshot
    ) -> some View {
        TDCard {
            VStack(alignment: .leading, spacing: TDSpacing.m) {
                Text("shop.refill.title")
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.textPrimary)

                Text("shop.refill.description")
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)

                HStack(spacing: TDSpacing.s) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(TDColor.gold)
                    Text(String(localized: "shop.refill.cost \(snapshot.refillCost)"))
                        .font(TDTypography.secondary)
                        .fontWeight(.bold)
                        .foregroundStyle(TDColor.textPrimary)
                    Spacer()
                }
                .accessibilityIdentifier("shop.refill.price")

                if viewModel.lastRefillSucceeded {
                    Text("shop.refill.success")
                        .font(TDTypography.secondary)
                        .foregroundStyle(TDColor.success)
                        .accessibilityIdentifier("shop.refill.success")
                }

                if snapshot.isHeartsFull {
                    TDButton("shop.refill.button", style: .disabled) {}
                        .accessibilityIdentifier("shop.refill.button")
                    Text("shop.refill.full")
                        .font(TDTypography.caption)
                        .foregroundStyle(TDColor.textSecondary)
                } else if !snapshot.canAffordRefill {
                    TDButton("shop.refill.button", style: .disabled) {}
                        .accessibilityIdentifier("shop.refill.button")
                    Text("shop.refill.insufficient")
                        .font(TDTypography.caption)
                        .foregroundStyle(TDColor.textSecondary)
                } else {
                    TDButton("shop.refill.button", style: .primary) {
                        viewModel.refillHearts()
                    }
                    .accessibilityIdentifier("shop.refill.button")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var loadingView: some View {
        VStack(spacing: TDSpacing.m) {
            ProgressView()
                .tint(TDColor.primary)
                .controlSize(.large)
            Text("shop.loading")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}
