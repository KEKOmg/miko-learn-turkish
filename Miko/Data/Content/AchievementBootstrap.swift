import Foundation
import SwiftData

/// Idempotently seeds the `Achievement` catalog from `AchievementCatalog`.
/// Safe to call on every launch: existing rows are kept (and their
/// definition fields refreshed to match the catalog), missing rows are
/// inserted, and no duplicate `key` is ever created.
enum AchievementBootstrap {

    @MainActor
    static func bootstrapIfNeeded(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Achievement>())
        var byKey: [String: Achievement] = [:]
        for achievement in existing { byKey[achievement.key] = achievement }

        for entry in AchievementCatalog.entries {
            if let existing = byKey[entry.key] {
                existing.titleKey = entry.titleKey
                existing.descriptionKey = entry.descriptionKey
                existing.conditionTypeRaw = entry.condition.rawValue
                existing.conditionValue = entry.conditionValue
                existing.icon = entry.icon
            } else {
                let achievement = Achievement(
                    key: entry.key,
                    titleKey: entry.titleKey,
                    descriptionKey: entry.descriptionKey,
                    conditionTypeRaw: entry.condition.rawValue,
                    conditionValue: entry.conditionValue,
                    icon: entry.icon
                )
                context.insert(achievement)
            }
        }

        try context.save()
    }
}
