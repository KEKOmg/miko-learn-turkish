import SwiftUI
import SwiftData

/// Profile screen.
///
/// Shows the user's XP, streak, hearts, completed-lesson count, and the full
/// achievement catalog with earned/locked states. All data flows from
/// `ProfileViewModel` as immutable snapshots — the view never touches
/// SwiftData directly.
struct ProfileView: View {
    var isActive: Bool = true

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appContainer) private var appContainer
    @Environment(AuthStore.self) private var authStore
    @Query private var settingsRows: [UserSettings]
    @Query private var dailyGoals: [DailyGoal]

    @State private var viewModel: ProfileViewModel?
    @State private var isSettingsPresented = false
    @State private var isAuthPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: TDSpacing.l) {
                if let viewModel, let snapshot = viewModel.snapshot {
                    content(snapshot: snapshot)
                } else {
                    loadingView
                }
            }
            .padding(.horizontal, TDSpacing.l)
            .padding(.top, TDSpacing.l)
            .padding(.bottom, TDSpacing.xxl)
        }
        .background(TDColor.background)
        .sheet(isPresented: $isSettingsPresented) {
            if let settings = activeSettings {
                SettingsView(settings: settings, dailyGoal: activeDailyGoal)
            } else {
                ContentUnavailableView(
                    "settings.unavailable.title",
                    systemImage: "gearshape",
                    description: Text("settings.unavailable.message")
                )
            }
        }
        .sheet(isPresented: $isAuthPresented) {
            AuthView()
        }
        .task(id: isActive) {
            guard isActive else { return }
            if viewModel == nil {
                let vm = ProfileViewModel(
                    lessonProgressRepository: appContainer?.lessonProgressRepository
                        ?? LessonProgressRepository(
                            context: modelContext,
                            profileID: appState.activeProfileID
                        ),
                    achievementRepository: appContainer?.achievementRepository
                        ?? AchievementRepository(context: modelContext),
                    heartsRepository: appContainer?.heartsRepository
                )
                viewModel = vm
                vm.load()
            } else {
                viewModel?.load()
            }
            await syncAccountProgress()
        }
        .onChange(of: authStore.state) { _, newState in
            guard case .signedIn = newState else { return }
            Task { await syncAccountProgress() }
        }
        .onChange(of: appState.restoredProgressRevision) { _, _ in
            viewModel?.load()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(snapshot: ProfileSnapshot) -> some View {
        header
        AccountCardView(
            onOpenAuth: { isAuthPresented = true },
            onSync: {
                Task { await syncAccountProgress() }
            }
        )
        statsCard(snapshot.stat)
        achievementsSection(snapshot: snapshot)
    }

    @MainActor
    private func syncAccountProgress() async {
        // This task can outlive the view during account switching. Never
        // pair its old UI snapshot with the newly signed-in user's UUID.
        guard let user = authStore.user,
              appState.activeProfileID == user.id,
              let local = ProgressRestoreService.currentLocalProgress(
                context: modelContext,
                profileID: user.id
              ) else { return }
        await authStore.sync(
            progress: CloudProgress(
                username: user.username.isEmpty
                    ? String(localized: "auth.account.user")
                    : user.username,
                xp: local.xp,
                streakDays: local.streakDays,
                lessonsCompleted: local.lessonsCompleted
            ),
            ownerUserID: user.id
        )
    }

    private var activeSettings: UserSettings? {
        guard let profileID = appState.activeProfileID else { return nil }
        return settingsRows.first { $0.user?.id == profileID }
    }

    private var activeDailyGoal: DailyGoal? {
        guard let profileID = appState.activeProfileID else { return nil }
        return dailyGoals.first { $0.user?.id == profileID }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: TDSpacing.m) {
            Text("profile.title")
                .font(TDTypography.largeTitle)
                .foregroundStyle(TDColor.screenTitle)
                .accessibilityIdentifier("profile.header")

            Spacer()

            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(TDColor.primary))
            }
            .accessibilityLabel("settings.open")
            .accessibilityIdentifier("profile.settings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statsCard(_ stat: ProfileSnapshot.Stat) -> some View {
        TDCard {
            VStack(alignment: .leading, spacing: TDSpacing.m) {
                Text("profile.section.stats")
                    .font(TDTypography.sectionTitle)
                    .foregroundStyle(TDColor.textPrimary)

                HStack(spacing: TDSpacing.l) {
                    statTile(
                        icon: "bolt.fill",
                        label: "profile.stat.xp",
                        value: "\(stat.xp)",
                        tint: TDColor.primary,
                        identifier: "profile.stat.xp"
                    )
                    statTile(
                        icon: "flame.fill",
                        label: "profile.stat.streak",
                        value: "\(stat.streakDays)",
                        tint: TDColor.warning,
                        identifier: "profile.stat.streak"
                    )
                }
                HStack(spacing: TDSpacing.l) {
                    statTile(
                        icon: "heart.fill",
                        label: "profile.stat.hearts",
                        value: "\(stat.heartsRemaining)/\(stat.heartsTotal)",
                        tint: TDColor.coral,
                        identifier: "profile.stat.hearts"
                    )
                    statTile(
                        icon: "books.vertical.fill",
                        label: "profile.stat.lessons",
                        value: "\(stat.lessonsCompleted)",
                        tint: TDColor.success,
                        identifier: "profile.stat.lessons"
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.stats")
    }

    private func statTile(
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
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Achievements

    @ViewBuilder
    private func achievementsSection(snapshot: ProfileSnapshot) -> some View {
        VStack(alignment: .leading, spacing: TDSpacing.m) {
            HStack {
                Text("profile.section.achievements")
                    .font(TDTypography.sectionTitle)
                    .foregroundStyle(TDColor.textPrimary)
                Spacer()
                Text(String(localized: "profile.achievements.earned \(snapshot.earnedCount)"))
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)
                    .accessibilityIdentifier("profile.achievements.earnedCount")
            }

            if snapshot.achievements.isEmpty {
                Text("profile.achievements.empty")
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)
                    .padding(.vertical, TDSpacing.l)
            } else {
                VStack(spacing: TDSpacing.m) {
                    ForEach(snapshot.achievements) { row in
                        AchievementRowView(row: row)
                            .accessibilityIdentifier("profile.achievement.\(row.key)")
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: TDSpacing.m) {
            ProgressView()
                .tint(TDColor.primary)
                .controlSize(.large)
            Text("profile.loading")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

/// A single achievement row: badge + title/description or progress bar.
/// Locked rows are muted.
struct AchievementRowView: View {
    let row: ProfileSnapshot.AchievementRow

    private var isEarned: Bool {
        if case .earned = row.kind { return true }
        return false
    }

    private var progress: Double {
        if case .locked(let p) = row.kind { return p }
        return 1
    }

    var body: some View {
        TDCard {
            HStack(spacing: TDSpacing.m) {
                TDAchievementBadge(icon: row.icon, earned: isEarned, size: 56)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: TDSpacing.xs) {
                    Text(LocalizedStringKey(row.titleKey))
                        .font(TDTypography.cardTitle)
                        .foregroundStyle(isEarned ? TDColor.textPrimary : TDColor.disabledText)
                        .accessibilityLabel("a11y.achievement.title")

                    Text(LocalizedStringKey(row.descriptionKey))
                        .font(TDTypography.caption)
                        .foregroundStyle(isEarned ? TDColor.textSecondary : TDColor.disabledText)
                        .accessibilityLabel("a11y.achievement.description")

                    if !isEarned {
                        TDProgressBar(progress: progress, tint: TDColor.primary)
                            .accessibilityLabel("a11y.achievement.progress")
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

}

/// Basic user-facing preferences backed by the existing SwiftData
/// `UserSettings` model. Changes are saved when the sheet closes.
private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tdSystemColorScheme) private var systemColorScheme

    @Bindable var settings: UserSettings
    let dailyGoal: DailyGoal?

    private let goalOptions = [50, 100, 200, 400]
    @AppStorage("appearance.colorScheme") private var colorSchemePreference =
        AppColorSchemePreference.system.rawValue
    @State private var reminderPulse = false
    @State private var notificationStatusKey: LocalizedStringKey?
    @State private var isApplyingPermissionDenial = false
    @State private var appearanceSelection = AppColorSchemePreference.system.rawValue
    @State private var appearanceUpdateTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 0) {
                        ReminderPreviewCard(
                            isActive: settings.notificationsEnabled,
                            time: reminderTime,
                            reduceMotion: settings.reduceMotion,
                            isPulsing: reminderPulse
                        )
                        .padding(TDSpacing.m)

                        Divider()
                            .padding(.leading, TDSpacing.m)

                        Toggle("settings.notifications", isOn: $settings.notificationsEnabled)
                            .padding(TDSpacing.m)

                        if settings.notificationsEnabled {
                            Divider()
                                .padding(.leading, TDSpacing.m)

                            DatePicker(
                                "settings.reminder.time",
                                selection: Binding(
                                    get: { reminderTime },
                                    set: { newValue in
                                        settings.dailyGoalReminderTime = newValue
                                        try? modelContext.save()
                                        Task { await updateReminder() }
                                    }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .padding(TDSpacing.m)
                        }

                        if let notificationStatusKey {
                            Divider()
                                .padding(.leading, TDSpacing.m)

                            Text(notificationStatusKey)
                                .font(TDTypography.caption)
                                .foregroundStyle(
                                    settings.notificationsEnabled
                                        ? TDColor.success
                                        : TDColor.textSecondary
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(TDSpacing.m)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: TDCornerRadius.card)
                            .fill(TDColor.secondarySurface)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: TDCornerRadius.card)
                            .stroke(
                                settings.notificationsEnabled
                                    ? TDColor.gold.opacity(0.8)
                                    : Color.clear,
                                lineWidth: 2
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TDCornerRadius.card))
                    .listRowInsets(
                        EdgeInsets(
                            top: TDSpacing.s,
                            leading: TDSpacing.m,
                            bottom: TDSpacing.s,
                            trailing: TDSpacing.m
                        )
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    Text("settings.section.reminders")
                } footer: {
                    Text("settings.reminder.description")
                }

                Section("settings.section.learning") {
                    Toggle("settings.audio", isOn: $settings.audioEnabled)
                    Toggle("settings.sound", isOn: $settings.soundOn)
                    Toggle("settings.haptics", isOn: $settings.hapticsEnabled)
                }

                Section {
                    ThemePreferenceControl(selection: $appearanceSelection)
                } header: {
                    Text("settings.section.appearance")
                } footer: {
                    Text("settings.appearance.description")
                }

                Section {
                    Toggle("settings.reduceMotion", isOn: $settings.reduceMotion)
                } header: {
                    Text("settings.section.accessibility")
                } footer: {
                    Text("settings.reduceMotion.description")
                }

                if let dailyGoal {
                    Section("settings.section.dailyGoal") {
                        Picker(
                            "settings.dailyGoal",
                            selection: Binding(
                                get: { dailyGoal.xpTarget },
                                set: {
                                    dailyGoal.xpTarget = $0
                                    try? modelContext.save()
                                }
                            )
                        ) {
                            ForEach(goalOptions, id: \.self) { xp in
                                Text("\(xp) XP").tag(xp)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings.done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                appearanceUpdateTask?.cancel()
                try? modelContext.save()
            }
            .onAppear {
                appearanceSelection = colorSchemePreference
                if settings.dailyGoalReminderTime == nil {
                    settings.dailyGoalReminderTime = Self.defaultReminderTime
                }
                reminderPulse = true
            }
            .onChange(of: settings.notificationsEnabled) { _, _ in
                if isApplyingPermissionDenial {
                    isApplyingPermissionDenial = false
                    return
                }
                Task { await updateReminder() }
            }
            .onChange(of: settings.soundOn) { _, _ in
                guard settings.notificationsEnabled else { return }
                Task { await updateReminder() }
            }
            .onChange(of: appearanceSelection) { _, newValue in
                scheduleAppearanceUpdate(newValue)
            }
        }
        .preferredColorScheme(selectedColorScheme)
    }

    private var selectedColorScheme: ColorScheme? {
        guard let preference = AppColorSchemePreference(rawValue: colorSchemePreference) else {
            return systemColorScheme
        }

        switch preference {
        case .system:
            return systemColorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func scheduleAppearanceUpdate(_ newValue: String) {
        appearanceUpdateTask?.cancel()
        guard newValue != colorSchemePreference else { return }

        let delay: Duration = settings.reduceMotion ? .zero : .milliseconds(280)
        appearanceUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                colorSchemePreference = newValue
            }
        }
    }

    private var reminderTime: Date {
        settings.dailyGoalReminderTime ?? Self.defaultReminderTime
    }

    @MainActor
    private func updateReminder() async {
        let scheduled = await DailyReminderScheduler.update(
            enabled: settings.notificationsEnabled,
            time: reminderTime,
            soundEnabled: settings.soundOn
        )

        if settings.notificationsEnabled && !scheduled {
            isApplyingPermissionDenial = true
            settings.notificationsEnabled = false
            notificationStatusKey = "settings.reminder.permissionDenied"
        } else {
            notificationStatusKey = scheduled
                ? "settings.reminder.scheduled"
                : "settings.reminder.disabled"
        }
        try? modelContext.save()
    }

    private static var defaultReminderTime: Date {
        Calendar.current.date(
            bySettingHour: 19,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }
}

private struct ThemePreferenceControl: View {
    @Binding var selection: String

    var body: some View {
        Picker("settings.appearance.title", selection: $selection) {
            ForEach(AppColorSchemePreference.allCases) { preference in
                Text(preference.titleKey)
                    .tag(preference.rawValue)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct ReminderPreviewCard: View {
    let isActive: Bool
    let time: Date
    let reduceMotion: Bool
    let isPulsing: Bool

    var body: some View {
        HStack(spacing: TDSpacing.m) {
            ZStack {
                Circle()
                    .fill(TDColor.gold.opacity(isActive ? 0.28 : 0.12))
                    .frame(width: 62, height: 62)
                    .scaleEffect(isActive && isPulsing && !reduceMotion ? 1.12 : 1)
                    .opacity(isActive && isPulsing && !reduceMotion ? 0.72 : 1)

                Image(systemName: isActive ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(isActive ? TDColor.warning : TDColor.disabledText)
            }
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.15).repeatForever(autoreverses: true),
                value: isPulsing
            )

            VStack(alignment: .leading, spacing: TDSpacing.xs) {
                Text(LocalizedStringKey(
                    isActive
                        ? "settings.reminder.preview.active"
                        : "settings.reminder.preview.inactive"
                ))
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.textPrimary)

                Text(
                    isActive
                        ? String(localized: "settings.reminder.preview.time \(Self.timeFormatter.string(from: time))")
                        : String(localized: "settings.reminder.preview.hint")
                )
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
