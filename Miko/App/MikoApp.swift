import SwiftUI
import SwiftData

@main
struct MikoApp: App {
    let modelContainer: ModelContainer
    @State private var appState: AppState
    @State private var authStore: AuthStore
    private let container: AppContainer

    init() {
        FontRegistrar.registerFonts()
        let result = ModelContainerFactory.make()
        let mc = result.container
        self.modelContainer = mc
        let state = AppState()
        // Record how storage was opened so the UI can distinguish normal
        // operation from a recovered or ephemeral store.
        state.storeOutcome = result.outcome
        self.appState = state
        // Standard UI regressions intentionally run without production auth.
        // Their SwiftData store is fresh per launch, while the Simulator
        // Keychain can survive app reinstall/reset. Restoring that stale
        // session mid-lesson would switch `activeProfileID` and rebuild the
        // main shell, making deterministic navigation tests account-dependent.
        let isRunningStandardUITests = ProcessInfo.processInfo.arguments.contains("-UITestReset")
        self.authStore = AuthStore(
            configuration: isRunningStandardUITests ? nil : SupabaseConfiguration.load()
        )
        self.container = AppContainer(modelContainer: mc, appState: state)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(authStore)
                .environment(\.appContainer, container)
                .task {
                    await authStore.restoreSession()
                }
                .onOpenURL { url in
                    Task {
                        await authStore.handleAuthCallback(url)
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
