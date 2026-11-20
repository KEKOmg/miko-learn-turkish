import SwiftUI
import SwiftData

/// Shared launch point so Home and Course Map never duplicate lesson-flow
/// navigation. Presenting is centralized in `MainTabView` via
/// `.lessonFlowLauncher()`; screens only set `appState.activeLessonID`.
struct LessonFlowLauncher: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content.fullScreenCover(
            isPresented: Binding(
                get: { appState.activeLessonID != nil },
                set: { if !$0 { appState.activeLessonID = nil } }
            )
        ) {
            if let lessonID = appState.activeLessonID {
                LessonFlowView(lessonID: lessonID, mode: appState.activeLessonMode) {
                    appState.activeLessonID = nil
                    appState.activeLessonMode = .normal
                }
            }
        }
    }
}

extension View {
    /// Presents the immersive lesson flow for `appState.activeLessonID`.
    func lessonFlowLauncher() -> some View {
        modifier(LessonFlowLauncher())
    }
}
