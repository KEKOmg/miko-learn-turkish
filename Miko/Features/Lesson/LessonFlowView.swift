import SwiftUI
import SwiftData

/// Immersive lesson flow screen: top bar (close, progress, counter, hearts),
/// the current exercise rendered by `ExerciseFactory`, and error states.
/// Exercise views own their feedback + Continue interaction; the ViewModel
/// owns sequencing.
struct LessonFlowView: View {
    let lessonID: UUID
    var mode: LessonSessionMode = .normal
    var onClose: () -> Void

    @State private var viewModel: LessonFlowViewModel?
    @State private var audioProvider = AVAudioProvider()
    @State private var speechProvider: any SpeechProviding = {
        if ProcessInfo.processInfo.arguments.contains("-UITestReset") {
            return MockSpeechProvider()
        }
        return AppleSpeechProvider()
    }()
    @State private var isGrammarSheetPresented = false
    @State private var isQuitConfirmPresented = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appContainer) private var appContainer
    @Environment(AuthStore.self) private var authStore
    @Environment(AppState.self) private var appState
    @Environment(\.tdReduceMotion) private var reduceMotion
    @State private var hasSyncedCompletedRun = false

    var body: some View {
        Group {
            switch viewModel?.phase {
            case .loading, nil:
                loadingView

            case .playing:
                playingView

            case .completed(let outcome):
                LessonResultsView(outcome: outcome, showsPersistenceWarning: viewModel?.persistenceFailed == true) {
                    onClose()
                }

            case .depleted:
                HeartsDepletedView(
                    secondsUntilNextHeart: viewModel?.secondsUntilNextHeart ?? 0,
                    onLeave: { onClose() }
                )

            case .failed(let message):
                errorView(message)
            }
        }
        .background(TDColor.background.ignoresSafeArea())
        .task {
            guard let viewModel else {
                let repository = LessonProgressRepository(
                    context: modelContext,
                    profileID: appState.activeProfileID
                )
                let hearts = appContainer?.heartsRepository
                let service = appContainer?.gamificationService
                let vm = LessonFlowViewModel(
                    repository: repository,
                    heartsRepository: hearts,
                    gamificationService: service
                )
                viewModel = vm
                vm.load(lessonID: lessonID, mode: mode)
                configureAudio(using: vm)
                return
            }
            guard viewModel.totalCount == 0 else { return }
            viewModel.load(lessonID: lessonID, mode: mode)
            configureAudio(using: viewModel)
        }
        .sheet(isPresented: $isGrammarSheetPresented) {
            if let topic = viewModel?.grammarTopic {
                GrammarSheet(topic: topic)
            }
        }
        .onChange(of: viewModel?.phase) { _, newPhase in
            guard case .completed = newPhase, !hasSyncedCompletedRun else { return }
            hasSyncedCompletedRun = true
            Task { await syncCompletedRun() }
        }
        .alert("lessonflow.quit.title", isPresented: $isQuitConfirmPresented) {
            Button("lessonflow.quit.stay", role: .cancel) {}
            Button("lessonflow.quit.confirm", role: .destructive) {
                onClose()
            }
        } message: {
            Text("lessonflow.quit.message")
        }
    }

    // MARK: - Playing

    private var playingView: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, TDSpacing.m)
                .padding(.top, TDSpacing.s)
                .padding(.bottom, TDSpacing.m)

            if let viewModel, let exercise = viewModel.currentExercise {
                GeometryReader { proxy in
                    ScrollView {
                        ExerciseFactory.makeView(
                            exercise: exercise,
                            audioProvider: audioProvider,
                            audioEnabled: viewModel.audioEnabled,
                            voicePronunciationEnabled: viewModel.soundOn,
                            speechProvider: speechProvider
                        ) { result in
                            viewModel.submitAndAdvance(result)
                        }
                        .frame(minHeight: proxy.size.height)
                        .padding(.bottom, TDSpacing.xxl)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("lessonflow.exerciseScroll")
                    // A new exercise must begin at its prompt, even when the
                    // previous exercise was scrolled down to Check/Continue.
                    .id(exercise.key)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("lessonflow.root")
                .allowsHitTesting(false)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85),
            value: viewModel?.currentIndex
        )
        .onChange(of: viewModel?.currentIndex) { _, _ in
            // Dismiss the keyboard when advancing so it doesn't persist into
            // non-text exercises and intercept touches.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
            audioProvider.stopAudio()
            speechProvider.stopRecognition()
        }
    }

    private func configureAudio(using viewModel: LessonFlowViewModel) {
        audioProvider.isAudioEnabled = viewModel.audioEnabled
        // Listening exercises currently use Turkish text-to-speech whenever
        // a recorded clip is not bundled. That fallback is required lesson
        // audio and follows the "Exercise audio" setting. The separate
        // voice-pronunciation setting is applied only to optional word audio
        // in ExerciseFactory.
        audioProvider.isSpeechEnabled = viewModel.audioEnabled
    }

    @MainActor
    private func syncCompletedRun() async {
        guard let account = authStore.user,
              appState.activeProfileID == account.id,
              let local = ProgressRestoreService.currentLocalProgress(
                context: modelContext,
                profileID: account.id
              ) else {
            return
        }
        await authStore.sync(
            progress: CloudProgress(
                username: account.username.isEmpty
                    ? String(localized: "auth.account.user")
                    : account.username,
                xp: local.xp,
                streakDays: local.streakDays,
                lessonsCompleted: local.lessonsCompleted
            ),
            ownerUserID: account.id
        )
        if let completed = try? ProgressRestoreService.currentLocalLessonProgress(
            context: modelContext,
            profileID: account.id
        ) {
            await authStore.syncLessonProgress(completed, ownerUserID: account.id)
        }
    }

    private var topBar: some View {
        HStack(spacing: TDSpacing.m) {
            Button(action: { isQuitConfirmPresented = true }) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(TDColor.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(TDColor.secondarySurface))
            }
            .accessibilityLabel("lessonflow.close")
            .accessibilityIdentifier("lessonflow.close")

            TDProgressBar(progress: viewModel?.progress ?? 0, tint: TDColor.primary)

            if let viewModel {
                Text(String(localized: "progress.count \(viewModel.currentIndex + 1) \(viewModel.totalCount)"))
                    .font(TDTypography.secondary)
                    .fontWeight(.bold)
                    .foregroundStyle(TDColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("lessonflow.counter")
                    .accessibilityValue(
                        String(localized: "progress.count \(viewModel.currentIndex + 1) \(viewModel.totalCount)")
                    )
                    .accessibilityIdentifier("lessonflow.counter")
            }

            if viewModel?.grammarTopic != nil {
                Button {
                    isGrammarSheetPresented = true
                } label: {
                    Image(systemName: "book.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(TDColor.primary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(TDColor.secondarySurface))
                }
                .accessibilityLabel("lessonflow.grammar")
            }

            TDHeartView(total: viewModel?.totalHearts ?? 5, remaining: viewModel?.remainingHearts ?? 5)
        }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: TDSpacing.m) {
            ProgressView()
                .tint(TDColor.primary)
                .controlSize(.large)
            Text("lessonflow.loading")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: TDSpacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(TDColor.error)

            Text("lessonflow.error.title")
                .font(TDTypography.sectionTitle)
                .foregroundStyle(TDColor.textPrimary)

            Text(message)
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
                .multilineTextAlignment(.center)

            TDButton("lessonflow.error.close", style: .primary) {
                onClose()
            }
            .padding(.horizontal, TDSpacing.xl)
        }
        .padding(TDSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
