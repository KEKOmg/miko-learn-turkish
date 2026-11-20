import Foundation
import SwiftData

/// Imports seed content on first launch and refreshes existing rows whenever
/// the bundled course version increases. User progress is preserved because
/// `ContentImporter` updates content by stable keys.
enum ContentBootstrap {

    private static let courseKey = "course.ru-tr"

    /// Idempotent — imports only when the course is missing or the bundled
    /// content version is newer than the persisted version.
    @MainActor
    static func bootstrapIfNeeded(context: ModelContext) throws {
        let bundle = try BundleContentSource().load()
        let repo = CourseRepository(context: context)
        if let storedCourse = try repo.fetchCourse(byKey: courseKey),
           storedCourse.version >= bundle.course.version,
           hasCompleteCourseGraph(storedCourse, for: bundle) {
            return
        }
        try ContentImporter.import(bundle, into: context)
    }

    /// A version number alone is not enough while content is being developed:
    /// an older build may already have persisted that version before every
    /// level relationship was bundled. Verify the displayable course graph as
    /// well so missing levels (notably A2) self-heal on the next launch.
    static func hasCompleteCourseGraph(_ course: Course, for bundle: ContentBundle) -> Bool {
        let persistedLevels = course.levels
        let persistedUnits = persistedLevels.flatMap(\.units)
        let persistedLessons = persistedUnits.flatMap(\.lessons)

        return Set(bundle.levels.map(\.key)).isSubset(of: Set(persistedLevels.map(\.key)))
            && Set(bundle.units.map(\.key)).isSubset(of: Set(persistedUnits.map(\.key)))
            && Set(bundle.lessons.map(\.key)).isSubset(of: Set(persistedLessons.map(\.key)))
    }

    /// Force-imports the bundled seed data regardless of current state.
    /// All existing entities matched by key will be updated.
    @MainActor
    static func forceImport(context: ModelContext) throws {
        let bundle = try BundleContentSource().load()
        try ContentImporter.import(bundle, into: context)
    }
}
