import SwiftUI

/// Environment injection for `AppContainer` so views and ViewModels can
/// obtain gamification services and repositories without constructing them
/// directly on `@Environment(\.modelContext)`.
private struct AppContainerKey: EnvironmentKey {
    // The default is `nil`; the container itself is only ever shared through
    // the main-actor environment, so the unsafe marker is sound here.
    nonisolated(unsafe) static let defaultValue: AppContainer? = nil
}

extension EnvironmentValues {
    var appContainer: AppContainer? {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}
