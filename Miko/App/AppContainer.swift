import Foundation
import SwiftData

/// Dependency-injection container. Holds the `ModelContainer` and `AppState`
/// and provides repository / service factories built on the main context.
/// Views and ViewModels obtain their dependencies from here instead of
/// constructing repositories directly on `@Environment(\.modelContext)`.
final class AppContainer {
    /// Temporary manual-testing aid. Debug builds keep hearts full; release
    /// builds always use the normal heart economy.
    #if DEBUG
    private static let unlimitedHeartsForTesting = true
    #else
    private static let unlimitedHeartsForTesting = false
    #endif

    let modelContainer: ModelContainer
    let appState: AppState

    init(modelContainer: ModelContainer, appState: AppState = AppState()) {
        self.modelContainer = modelContainer
        self.appState = appState
    }

    @MainActor
    var mainContext: ModelContext {
        modelContainer.mainContext
    }

    @MainActor
    var courseRepository: CourseRepository {
        CourseRepository(context: mainContext)
    }

    @MainActor
    var lessonProgressRepository: LessonProgressRepository {
        LessonProgressRepository(context: mainContext, profileID: appState.activeProfileID)
    }

    @MainActor
    var heartsRepository: HeartsRepository {
        HeartsRepository(
            context: mainContext,
            unlimitedHearts: Self.unlimitedHeartsForTesting
        )
    }

    @MainActor
    var gamificationRepository: GamificationRepository {
        GamificationRepository(context: mainContext, profileID: appState.activeProfileID)
    }

    @MainActor
    var achievementRepository: AchievementRepository {
        AchievementRepository(context: mainContext)
    }

    @MainActor
    var gamificationService: GamificationService {
        GamificationService(
            gamificationRepository: gamificationRepository,
            achievementRepository: achievementRepository
        )
    }
}
