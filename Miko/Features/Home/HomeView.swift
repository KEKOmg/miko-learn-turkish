import SwiftUI
import SwiftData
import Combine

/// Home screen.
///
/// Shows the brand header, streak/XP/hearts stats, the daily goal card, the
/// XP reward card, a friendly mascot speech bubble, and a large "start the
/// next lesson" CTA. The CTA launches the real next unfinished lesson
/// through the shared lesson flow (`appState.activeLessonID`). When the user
/// has no hearts the CTA is disabled and a regeneration countdown is shown.
struct HomeView: View {
    var isActive: Bool = true
    var onShowCourseMap: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appContainer) private var appContainer

    @State private var viewModel: HomeViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: TDSpacing.m) {
                if let viewModel, let stats = viewModel.stats {
                    content(viewModel: viewModel, stats: stats)
                } else {
                    loadingView
                }
            }
            .padding(.horizontal, TDSpacing.l)
            .padding(.top, TDSpacing.l)
            .padding(.bottom, TDSpacing.xxl)
        }
        .accessibilityIdentifier("home.scroll")
        .background(TDColor.background)
        .task(id: isActive) {
            guard isActive else { return }
            if viewModel == nil {
                let vm = makeViewModel()
                viewModel = vm
                vm.load()
            } else {
                viewModel?.load()
            }
        }
        .onChange(of: appState.activeLessonID) { _, newValue in
            // Refresh when the lesson flow closes so the Home reflects the
            // newly-awarded XP, streak, and hearts.
            if newValue == nil {
                viewModel?.load()
            }
        }
        .onChange(of: appState.restoredProgressRevision) { _, _ in
            viewModel?.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if isActive && newPhase == .active {
                viewModel?.load()
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            // Heart recovery is time-based, so an open Home must refresh even
            // when the user neither switches tabs nor relaunches the app.
            if isActive && scenePhase == .active &&
                viewModel?.stats.map({ $0.heartsRemaining < $0.heartsTotal }) == true {
                viewModel?.load()
            }
        }
    }

    private func makeViewModel() -> HomeViewModel {
        HomeViewModel(
            repository: appContainer?.lessonProgressRepository
                ?? LessonProgressRepository(
                    context: modelContext,
                    profileID: appState.activeProfileID
                ),
            heartsRepository: appContainer?.heartsRepository,
            gamificationRepository: appContainer?.gamificationRepository
        )
    }

    // MARK: - Content

    @ViewBuilder
    private func content(viewModel: HomeViewModel, stats: UserStatsSnapshot) -> some View {
        header
        StatsHeader(stats: stats)

        DailyGoalCard(stats: stats)
        XPRewardCard(
            canClaim: viewModel.canClaimDailyReward,
            isClaimed: viewModel.isDailyRewardClaimed,
            rewardGems: HomeViewModel.dailyRewardGems,
            xpRemaining: viewModel.xpUntilDailyReward,
            onClaim: viewModel.claimDailyReward
        )

        mascotSection(viewModel: viewModel)

        startCTA(viewModel: viewModel)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: TDSpacing.s) {
            Text("app.name")
                .font(TDTypography.largeTitle)
                .foregroundStyle(TDColor.screenTitle)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.header")
    }

    private func mascotSection(viewModel: HomeViewModel) -> some View {
        let isOutOfHearts = viewModel.nextLesson != nil && !viewModel.canStartLesson

        return VStack(spacing: TDSpacing.s) {
            SpeechBubble(
                text: viewModel.nextLesson == nil
                    ? LocalizedStringKey("home.course.completed")
                    : isOutOfHearts
                        ? LocalizedStringKey("home.hearts.depleted")
                        : LocalizedStringKey("home.mascot.greeting")
            )
            HStack {
                MascotView(mood: isOutOfHearts ? .sad : .wave, size: 80)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func startCTA(viewModel: HomeViewModel) -> some View {
        VStack(spacing: TDSpacing.s) {
            if let nextLesson = viewModel.nextLesson {
                if viewModel.canStartLesson {
                    TDButton("home.cta.start", style: .primary) {
                        appState.activeLessonID = nextLesson.id
                    }
                    .accessibilityIdentifier("home.startLesson")
                    .accessibilityHint(Text("home.cta.start.hint"))

                    Text(localizedLessonTitle(nextLesson.titleKey))
                        .font(TDTypography.secondary)
                        .foregroundStyle(TDColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("home.nextLesson.title")
                } else {
                    // Out of hearts: disabled CTA + regeneration info.
                    TDButton("home.cta.start", style: .secondary) {}
                        .disabled(true)
                        .accessibilityIdentifier("home.startLesson")
                        .accessibilityHint(Text("home.cta.disabled.hearts"))

                    heartsRegenerationInfo(viewModel: viewModel)
                }
            } else {
                TDButton("home.cta.review", style: .secondary, action: onShowCourseMap)
                    .accessibilityIdentifier("home.reviewCourse")
            }
        }
    }

    @ViewBuilder
    private func heartsRegenerationInfo(viewModel: HomeViewModel) -> some View {
        let seconds = viewModel.secondsUntilNextHeart
        if seconds > 0 {
            let minutes = Int(seconds) / 60
            HStack(spacing: TDSpacing.xs) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(TDColor.coral)
                Text(String(localized: "home.hearts.regenerating \(minutes)"))
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)
            }
            .padding(.horizontal, TDSpacing.m)
            .padding(.vertical, TDSpacing.xs)
            .background(Capsule().fill(TDColor.secondarySurface))
            .accessibilityIdentifier("home.hearts.regeneration")
        } else {
            Text("home.hearts.depleted")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
                .accessibilityIdentifier("home.hearts.depleted")
        }
    }

    private func localizedLessonTitle(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    private var loadingView: some View {
        VStack(spacing: TDSpacing.m) {
            ProgressView()
                .tint(TDColor.primary)
                .controlSize(.large)
            Text("home.loading")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}
