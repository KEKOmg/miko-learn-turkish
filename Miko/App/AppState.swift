import Foundation
import Observation

@Observable
final class AppState {
    enum BootstrapState: Equatable {
        case pending
        case loading
        case ready
        case failed(String)
    }

    var isOnboardingComplete: Bool = false
    var hasActiveCourse: Bool = false

    /// ID of the lesson currently presented in the immersive flow, if any.
    /// Set by any screen that launches a lesson; `MainTabView` owns the
    /// single `fullScreenCover` that presents it.
    var activeLessonID: UUID? = nil
    /// Session mode for the active lesson. `.normal` for a new lesson,
    /// `.practice` for a replay of a completed lesson. Reset together with
    /// `activeLessonID` when the flow closes.
    var activeLessonMode: LessonSessionMode = .normal
    /// Local SwiftData profile currently visible to the app. Signed-in
    /// accounts use their Supabase UUID; signed-out usage uses a separate
    /// persisted guest UUID.
    var activeProfileID: UUID? = nil
    /// Invalidates immutable screen snapshots after cloud hydration.
    var restoredProgressRevision = 0
    var bootstrapState: BootstrapState = .pending
    var userProfile: UserProfile? = nil

    /// How the SwiftData store was opened at launch. Drives the one-time
    /// storage notice so a persistent-store failure is never silently
    /// presented as normal operation.
    var storeOutcome: ModelContainerFactory.StoreOutcome = .persistent

    /// Set to `true` once the user dismisses the storage notice, so it is
    /// shown at most once per launch.
    var hasDismissedStorageNotice: Bool = false

    /// True while the storage notice should be visible.
    var isShowingStorageNotice: Bool {
        storeOutcome.requiresUserNotice && !hasDismissedStorageNotice
    }

    var isReady: Bool {
        if case .ready = bootstrapState { return true }
        return false
    }

    var bootstrapError: String? {
        if case .failed(let message) = bootstrapState { return message }
        return nil
    }
}
