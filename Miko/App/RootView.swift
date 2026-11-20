import SwiftUI
import SwiftData

private struct SystemColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .light
}

extension EnvironmentValues {
    var tdSystemColorScheme: ColorScheme {
        get { self[SystemColorSchemeKey.self] }
        set { self[SystemColorSchemeKey.self] = newValue }
    }
}

enum AppColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "settings.appearance.system"
        case .light: "settings.appearance.light"
        case .dark: "settings.appearance.dark"
        }
    }
}

/// Root view that switches between bootstrap states.
/// Shows a loading indicator while content is being imported,
/// an error screen on failure, and the main app shell when ready.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthStore.self) private var authStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var ambientColorScheme
    @Query private var settingsRows: [UserSettings]
    @AppStorage("appearance.colorScheme") private var colorSchemePreference =
        AppColorSchemePreference.system.rawValue
    @AppStorage("onboarding.isComplete") private var isOnboardingComplete = false
    @State private var bootstrapProgress = 0.06
    @State private var lastRestoredUserID: UUID?

    var body: some View {
        @Bindable var appState = appState

        return Group {
            if case .passwordResetRequired = authStore.state {
                PasswordResetView()
            } else {
                switch appState.bootstrapState {
                case .pending, .loading:
                    BootstrapLoadingView(progress: bootstrapProgress)

                case .ready:
                    if shouldShowOnboarding {
                        OnboardingView(onComplete: completeOnboarding)
                    } else {
                        MainTabView()
                            .id(appState.activeProfileID)
                    }

                case .failed(let message):
                    BootstrapErrorView(message: message)
                }
            }
        }
        .onChange(of: authStore.state) { _, newState in
            guard newState != .loading else { return }
            Task { await activateLocalProfileAndRestore() }
        }
        .environment(
            \.tdReduceMotion,
            systemReduceMotion
                || activeSettings?.reduceMotion == true
                || isRunningStandardUITests
        )
        .environment(\.tdSystemColorScheme, deviceSystemColorScheme)
        .preferredColorScheme(selectedColorScheme)
        .task {
            guard appState.bootstrapState == .pending else { return }
            await runBootstrap()
        }
        // A degraded store must be reported explicitly rather than silently
        // behaving like a normal (but empty) launch.
        .alert(
            storageNoticeTitle,
            isPresented: Binding(
                get: { appState.isShowingStorageNotice },
                set: { if !$0 { appState.hasDismissedStorageNotice = true } }
            )
        ) {
            Button("storage.notice.dismiss", role: .cancel) {
                appState.hasDismissedStorageNotice = true
            }
        } message: {
            Text(storageNoticeMessage)
        }
    }

    private var selectedColorScheme: ColorScheme? {
        (AppColorSchemePreference(rawValue: colorSchemePreference) ?? .system).colorScheme
    }

    private var activeSettings: UserSettings? {
        guard let profileID = appState.activeProfileID else { return nil }
        return settingsRows.first { $0.user?.id == profileID }
    }

    private var shouldShowOnboarding: Bool {
        !isOnboardingComplete && !isRunningStandardUITests
    }

    private var isRunningStandardUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestReset")
    }

    private var deviceSystemColorScheme: ColorScheme {
        let activeScreenStyle = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen.traitCollection.userInterfaceStyle

        switch activeScreenStyle {
        case .dark: return ColorScheme.dark
        case .light: return ColorScheme.light
        default: return ambientColorScheme
        }
    }

    private var storageNoticeTitle: LocalizedStringKey {
        switch appState.storeOutcome {
        case .persistent: return ""
        case .recoveredFresh: return "storage.notice.recovered.title"
        case .inMemoryFallback: return "storage.notice.inMemory.title"
        }
    }

    private var storageNoticeMessage: LocalizedStringKey {
        switch appState.storeOutcome {
        case .persistent: return ""
        case .recoveredFresh: return "storage.notice.recovered.message"
        case .inMemoryFallback: return "storage.notice.inMemory.message"
        }
    }

    @MainActor
    private func runBootstrap() async {
        let clock = ContinuousClock()
        let minimumVisibleUntil = clock.now.advanced(by: .milliseconds(1_200))

        appState.bootstrapState = .loading
        setBootstrapProgress(0.12)
        await Task.yield()

        do {
            try ContentBootstrap.bootstrapIfNeeded(context: modelContext)
            setBootstrapProgress(0.45)
            await Task.yield()

            let guest = try UserBootstrap.bootstrapIfNeeded(context: modelContext)
            appState.activeProfileID = guest.id
            setBootstrapProgress(0.65)
            await Task.yield()

            try AchievementBootstrap.bootstrapIfNeeded(context: modelContext)
            setBootstrapProgress(0.82)
            await Task.yield()

            // Reset the daily goal on launch so a new day starts at 0 XP.
            let gamificationRepository = GamificationRepository(
                context: modelContext,
                profileID: appState.activeProfileID
            )
            if let user = try gamificationRepository.fetchPrimaryUserProfile() {
                try gamificationRepository.resetDailyGoalIfNeeded(for: user)
            }

            setBootstrapProgress(0.94)
            try? await clock.sleep(until: minimumVisibleUntil)
            setBootstrapProgress(1)
            try? await Task.sleep(for: .milliseconds(160))
            appState.isOnboardingComplete = !shouldShowOnboarding
            appState.bootstrapState = .ready

            // A session restored from the keychain at launch never fires the
            // onChange handler, so attempt a restore once bootstrap is done.
            await activateLocalProfileAndRestore()
        } catch {
            appState.bootstrapState = .failed(error.localizedDescription)
        }
    }

    /// Switches the entire local data graph when auth state changes. Account
    /// profiles use the Supabase UUID; signed-out usage always returns to the
    /// separate guest profile created during bootstrap.
    @MainActor
    private func activateLocalProfileAndRestore() async {
        guard appState.bootstrapState == .ready else { return }

        switch authStore.state {
        case .signedIn(let user):
            do {
                let profile = try UserBootstrap.accountProfile(
                    id: user.id,
                    username: user.username,
                    context: modelContext
                )
                if appState.activeProfileID != profile.id {
                    appState.activeLessonID = nil
                    appState.activeLessonMode = .normal
                    appState.activeProfileID = profile.id
                }
                await restoreCloudProgressIfReady(for: user.id)
            } catch {
                return
            }

        case .loading:
            return

        default:
            do {
                let guest = try UserBootstrap.bootstrapIfNeeded(context: modelContext)
                if appState.activeProfileID != guest.id {
                    appState.activeLessonID = nil
                    appState.activeLessonMode = .normal
                    appState.activeProfileID = guest.id
                }
                lastRestoredUserID = nil
            } catch {
                return
            }
        }
    }

    /// Pulls aggregate and completed-lesson state once per signed-in account.
    /// Lesson hydration writes persistence rows directly and never enters the
    /// gamification/reward pipeline.
    @MainActor
    private func restoreCloudProgressIfReady(for userID: UUID) async {
        guard appState.activeProfileID == userID else { return }
        guard lastRestoredUserID != userID else { return }

        let cloud = await authStore.fetchCloudProgress(ownerUserID: userID)
        guard appState.activeProfileID == userID, authStore.user?.id == userID else { return }
        let cloudLessons = await authStore.fetchCloudLessonProgress(ownerUserID: userID)
        guard appState.activeProfileID == userID, authStore.user?.id == userID else { return }
        // A partial network result is not a completed restore. Leaving
        // `lastRestoredUserID` untouched lets the next auth-state activation
        // retry both halves instead of silently skipping course hydration.
        guard let cloud, let cloudLessons else { return }

        do {
            let local = ProgressRestoreService.currentLocalProgress(
                context: modelContext,
                profileID: userID
            )
            let merged = ProgressRestoreService.merge(local: local, cloud: cloud)

            let _ = try ProgressRestoreService.apply(
                merged,
                context: modelContext,
                profileID: userID
            )
            if merged.xp > cloud.xp
                || merged.streakDays > cloud.streakDays
                || merged.lessonsCompleted > cloud.lessonsCompleted {
                await authStore.sync(progress: merged, ownerUserID: userID)
            }

            guard appState.activeProfileID == userID, authStore.user?.id == userID else { return }

            _ = try ProgressRestoreService.hydrateLessonProgress(
                cloudLessons,
                context: modelContext,
                profileID: userID
            )
            appState.restoredProgressRevision += 1
            let mergedRows = try ProgressRestoreService.currentLocalLessonProgress(
                context: modelContext,
                profileID: userID
            )
            await authStore.syncLessonProgress(mergedRows, ownerUserID: userID)
        } catch {
            return
        }

        guard appState.activeProfileID == userID, authStore.user?.id == userID else { return }
        lastRestoredUserID = userID
    }

    private func setBootstrapProgress(_ progress: Double) {
        withAnimation(.easeOut(duration: 0.35)) {
            bootstrapProgress = progress
        }
    }

    private func completeOnboarding() {
        isOnboardingComplete = true
        appState.isOnboardingComplete = true
    }
}

private struct BootstrapLoadingView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: TDSpacing.m) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)
                .accessibilityHidden(true)

            Text("bootstrap.loading")
                .font(TDTypography.sectionTitle)
                .foregroundStyle(TDColor.textPrimary)

            TDProgressBar(progress: progress, height: 8)
                .frame(width: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TDColor.background)
    }
}

private struct BootstrapErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: TDSpacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(TDColor.error)

            Text("bootstrap.error.title")
                .font(TDTypography.sectionTitle)
                .foregroundStyle(TDColor.textPrimary)

            Text(message)
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TDSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TDColor.background)
    }
}
