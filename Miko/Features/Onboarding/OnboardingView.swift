import SwiftUI
import SwiftData

/// A compact first-run flow that turns the user's choices into real app
/// settings before the main tab bar is shown.
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tdReduceMotion) private var reduceMotion
    @Query private var settingsRows: [UserSettings]
    @Query private var dailyGoals: [DailyGoal]

    @AppStorage("onboarding.startingLevel") private var storedStartingLevel =
        OnboardingExperience.beginner.rawValue

    let onComplete: () -> Void

    @State private var step = 0
    @State private var selectedGoal = 50
    @State private var selectedExperience = OnboardingExperience.beginner
    @State private var reminderEnabled = true
    @State private var reminderTime: Date = {
        Calendar.current.date(
            bySettingHour: 19,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }()
    @State private var isFinishing = false
    @State private var didLoadStoredValues = false

    private let goalOptions = [
        OnboardingGoalOption(xp: 50, titleKey: "onboarding.goal.light"),
        OnboardingGoalOption(xp: 100, titleKey: "onboarding.goal.regular"),
        OnboardingGoalOption(xp: 200, titleKey: "onboarding.goal.serious"),
        OnboardingGoalOption(xp: 400, titleKey: "onboarding.goal.intense")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                pageContent
                    .id(step)
                    .transition(pageTransition)
                    .padding(.horizontal, TDSpacing.l)
                    .padding(.vertical, TDSpacing.m)
            }
            .scrollIndicators(.hidden)

            navigation
                .padding(.horizontal, TDSpacing.l)
                .padding(.top, TDSpacing.s)
                .padding(.bottom, TDSpacing.l)
                .background(TDColor.background)
        }
        .background(TDColor.background.ignoresSafeArea())
        .onAppear(perform: loadStoredValues)
        .accessibilityIdentifier("onboarding.root")
    }

    private var header: some View {
        VStack(spacing: TDSpacing.m) {
            HStack {
                Text("app.name")
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.screenTitle)

                Spacer()

                Text("\(step + 1) / \(OnboardingStep.allCases.count)")
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)
                    .monospacedDigit()
            }

            HStack(spacing: TDSpacing.s) {
                ForEach(OnboardingStep.allCases) { item in
                    Capsule()
                        .fill(item.rawValue <= step ? TDColor.primary : TDColor.disabled)
                        .frame(height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, TDSpacing.l)
        .padding(.top, TDSpacing.m)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch OnboardingStep(rawValue: step) ?? .welcome {
        case .welcome:
            welcomePage
        case .goal:
            goalPage
        case .experience:
            experiencePage
        case .reminder:
            reminderPage
        }
    }

    private var welcomePage: some View {
        OnboardingPage(
            mascotMood: .wave,
            eyebrowKey: "onboarding.welcome.eyebrow",
            titleKey: "onboarding.welcome.title",
            bodyKey: "onboarding.welcome.body"
        ) {
            TDSecondaryCard {
                Label {
                    Text("onboarding.welcome.promise")
                        .font(TDTypography.body)
                        .foregroundStyle(TDColor.textPrimary)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(TDColor.warning)
                }
            }
        }
    }

    private var goalPage: some View {
        OnboardingPage(
            mascotMood: .cheer,
            eyebrowKey: "onboarding.goal.eyebrow",
            titleKey: "onboarding.goal.title",
            bodyKey: "onboarding.goal.body"
        ) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: TDSpacing.m
            ) {
                ForEach(goalOptions) { option in
                    Button {
                        selectGoal(option.xp)
                    } label: {
                        VStack(spacing: TDSpacing.s) {
                            Text("\(option.xp) XP")
                                .font(TDTypography.sectionTitle)
                                .foregroundStyle(TDColor.textPrimary)

                            Text(LocalizedStringKey(option.titleKey))
                                .font(TDTypography.secondary)
                                .foregroundStyle(TDColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .background(
                            RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                                .fill(
                                    selectedGoal == option.xp
                                        ? TDColor.primary.opacity(0.14)
                                        : TDColor.surface
                                )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                                .stroke(
                                    selectedGoal == option.xp
                                        ? TDColor.primary
                                        : TDColor.disabled.opacity(0.7),
                                    lineWidth: selectedGoal == option.xp ? 3 : 1
                                )
                        }
                    }
                    .buttonStyle(TDPressButtonStyle())
                    .accessibilityIdentifier("onboarding.goal.\(option.xp)")
                }
            }
        }
    }

    private var experiencePage: some View {
        OnboardingPage(
            mascotMood: .teacher,
            eyebrowKey: "onboarding.level.eyebrow",
            titleKey: "onboarding.level.title",
            bodyKey: "onboarding.level.body"
        ) {
            VStack(spacing: TDSpacing.m) {
                ForEach(OnboardingExperience.allCases) { experience in
                    onboardingSelectionCard(
                        icon: experience.icon,
                        titleKey: experience.titleKey,
                        subtitleKey: experience.subtitleKey,
                        isSelected: selectedExperience == experience
                    ) {
                        selectExperience(experience)
                    }
                    .accessibilityIdentifier("onboarding.level.\(experience.rawValue)")
                }
            }
        }
    }

    private var reminderPage: some View {
        OnboardingPage(
            mascotMood: .listening,
            eyebrowKey: "onboarding.reminder.eyebrow",
            titleKey: "onboarding.reminder.title",
            bodyKey: "onboarding.reminder.body"
        ) {
            TDCard {
                VStack(spacing: TDSpacing.m) {
                    Toggle("onboarding.reminder.toggle", isOn: $reminderEnabled)
                        .font(TDTypography.body)
                        .tint(TDColor.primary)

                    if reminderEnabled {
                        Divider()

                        DatePicker(
                            "onboarding.reminder.time",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .font(TDTypography.body)
                        .datePickerStyle(.compact)

                        Text("onboarding.reminder.permission")
                            .font(TDTypography.caption)
                            .foregroundStyle(TDColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var navigation: some View {
        HStack(spacing: TDSpacing.m) {
            if step > 0 {
                Button {
                    move(to: step - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(TDColor.textPrimary)
                        .frame(width: 54, height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: TDCornerRadius.button)
                                .fill(TDColor.secondarySurface)
                        )
                }
                .buttonStyle(TDPressButtonStyle())
                .accessibilityLabel("onboarding.back")
            }

            Button {
                if step == OnboardingStep.allCases.count - 1 {
                    Task { await finishOnboarding() }
                } else {
                    move(to: step + 1)
                }
            } label: {
                HStack(spacing: TDSpacing.s) {
                    if isFinishing {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(step == OnboardingStep.allCases.count - 1
                         ? "onboarding.finish"
                         : "onboarding.continue")
                        .font(TDTypography.button)

                    if !isFinishing {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: TDCornerRadius.button)
                        .fill(TDColor.primary)
                )
            }
            .buttonStyle(TDPressButtonStyle())
            .disabled(isFinishing)
            .accessibilityIdentifier("onboarding.continue")
        }
    }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private func onboardingSelectionCard(
        icon: String,
        titleKey: String,
        subtitleKey: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TDSpacing.m) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white : TDColor.primary)
                    .frame(width: 46, height: 46)
                    .background(
                        Circle().fill(isSelected ? TDColor.primary : TDColor.secondarySurface)
                    )

                VStack(alignment: .leading, spacing: TDSpacing.xs) {
                    Text(LocalizedStringKey(titleKey))
                        .font(TDTypography.cardTitle)
                        .foregroundStyle(TDColor.textPrimary)

                    Text(LocalizedStringKey(subtitleKey))
                        .font(TDTypography.secondary)
                        .foregroundStyle(TDColor.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(isSelected ? TDColor.primary : TDColor.disabled)
            }
            .padding(TDSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                    .fill(TDColor.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                    .stroke(isSelected ? TDColor.primary : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(TDPressButtonStyle())
    }

    private func move(to newStep: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
            step = min(max(newStep, 0), OnboardingStep.allCases.count - 1)
        }
    }

    private func selectGoal(_ xp: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            selectedGoal = xp
        }
    }

    private func selectExperience(_ experience: OnboardingExperience) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            selectedExperience = experience
        }
    }

    private func loadStoredValues() {
        guard !didLoadStoredValues else { return }
        didLoadStoredValues = true

        if let dailyGoal = dailyGoals.first {
            selectedGoal = dailyGoal.xpTarget
        }
        if let experience = OnboardingExperience(rawValue: storedStartingLevel) {
            selectedExperience = experience
        }
        if let settings = settingsRows.first,
           let storedReminderTime = settings.dailyGoalReminderTime {
            reminderTime = storedReminderTime
            reminderEnabled = settings.notificationsEnabled
        }
    }

    @MainActor
    private func finishOnboarding() async {
        guard !isFinishing else { return }
        isFinishing = true

        dailyGoals.first?.xpTarget = selectedGoal
        storedStartingLevel = selectedExperience.rawValue

        if let settings = settingsRows.first {
            settings.dailyGoalReminderTime = reminderTime
            let scheduled = await DailyReminderScheduler.update(
                enabled: reminderEnabled,
                time: reminderTime,
                soundEnabled: settings.soundOn
            )
            settings.notificationsEnabled = reminderEnabled && scheduled
        }

        do {
            try modelContext.save()
            onComplete()
        } catch {
            isFinishing = false
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    let mascotMood: MascotView.Mood
    let eyebrowKey: LocalizedStringKey
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey
    let content: Content

    init(
        mascotMood: MascotView.Mood,
        eyebrowKey: LocalizedStringKey,
        titleKey: LocalizedStringKey,
        bodyKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.mascotMood = mascotMood
        self.eyebrowKey = eyebrowKey
        self.titleKey = titleKey
        self.bodyKey = bodyKey
        self.content = content()
    }

    var body: some View {
        VStack(spacing: TDSpacing.l) {
            MascotView(mood: mascotMood, size: 210)

            VStack(spacing: TDSpacing.s) {
                Text(eyebrowKey)
                    .font(TDTypography.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(TDColor.primary)
                    .textCase(.uppercase)

                Text(titleKey)
                    .font(TDTypography.title)
                    .foregroundStyle(TDColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text(bodyKey)
                    .font(TDTypography.body)
                    .foregroundStyle(TDColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .frame(maxWidth: .infinity)
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case goal
    case experience
    case reminder

    var id: Int { rawValue }
}

private enum OnboardingExperience: String, CaseIterable, Identifiable {
    case beginner
    case basics
    case confident

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .beginner: "sparkle"
        case .basics: "text.book.closed.fill"
        case .confident: "bubble.left.and.bubble.right.fill"
        }
    }

    var titleKey: String {
        switch self {
        case .beginner: "onboarding.level.beginner.title"
        case .basics: "onboarding.level.basics.title"
        case .confident: "onboarding.level.confident.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .beginner: "onboarding.level.beginner.subtitle"
        case .basics: "onboarding.level.basics.subtitle"
        case .confident: "onboarding.level.confident.subtitle"
        }
    }
}

private struct OnboardingGoalOption: Identifiable {
    let xp: Int
    let titleKey: String

    var id: Int { xp }
}
