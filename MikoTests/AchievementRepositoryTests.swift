import Foundation
import SwiftData
import Testing
@testable import Miko

/// Tests for `AchievementBootstrap` (idempotent seeding) and
/// `AchievementRepository` (catalog fetch, awarding, duplicate protection,
/// perfect-lesson count derivation).
@MainActor
struct AchievementRepositoryTests {

    private func makeContext() throws -> ModelContext {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    // MARK: - Bootstrap

    @Test func bootstrapSeedsAllEntries() throws {
        let context = try makeContext()
        try AchievementBootstrap.bootstrapIfNeeded(context: context)

        let catalog = try context.fetch(FetchDescriptor<Achievement>())
        #expect(catalog.count == AchievementCatalog.entries.count)
        for entry in AchievementCatalog.entries {
            #expect(catalog.contains { $0.key == entry.key })
        }
    }

    @Test func bootstrapIsIdempotent() throws {
        let context = try makeContext()
        try AchievementBootstrap.bootstrapIfNeeded(context: context)
        try AchievementBootstrap.bootstrapIfNeeded(context: context)
        try AchievementBootstrap.bootstrapIfNeeded(context: context)

        let catalog = try context.fetch(FetchDescriptor<Achievement>())
        #expect(catalog.count == AchievementCatalog.entries.count)
        // No duplicate keys.
        let keys = catalog.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test func bootstrapUpdatesExistingFields() throws {
        let context = try makeContext()
        // Insert a stale first_lesson row with outdated fields.
        let stale = Achievement(
            key: "first_lesson", titleKey: "old.title",
            descriptionKey: "old.description",
            conditionTypeRaw: "lessonsCompleted", conditionValue: 99,
            icon: "circle"
        )
        context.insert(stale)
        try context.save()

        try AchievementBootstrap.bootstrapIfNeeded(context: context)

        let catalog = try context.fetch(FetchDescriptor<Achievement>())
        #expect(catalog.count == AchievementCatalog.entries.count)
        let updated = catalog.first { $0.key == "first_lesson" }
        #expect(updated?.titleKey == "achievement.first_lesson.title")
        #expect(updated?.conditionValue == 1)
        #expect(updated?.icon == "flag.fill")
    }

    // MARK: - Catalog fetch

    @Test func fetchCatalogSortedByKey() throws {
        let context = try makeContext()
        try AchievementBootstrap.bootstrapIfNeeded(context: context)
        let repo = AchievementRepository(context: context)

        let catalog = try repo.fetchCatalog()
        let keys = catalog.map(\.key)
        let sortedKeys = keys.sorted()
        #expect(keys == sortedKeys)
    }

    // MARK: - Awarding

    @Test func awardCreatesUserAchievementRow() throws {
        let context = try makeContext()
        try AchievementBootstrap.bootstrapIfNeeded(context: context)
        let repo = AchievementRepository(context: context)

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        try context.save()

        let awarded = try repo.awardAchievements(keys: ["first_lesson", "xp_100"], for: user)
        #expect(awarded.count == 2)
        let earned = try repo.fetchEarnedAchievements(for: user)
        #expect(earned.count == 2)
        let keys = Set(earned.compactMap { $0.achievement?.key })
        #expect(keys == ["first_lesson", "xp_100"])
    }

    @Test func awardIsIdempotentForAlreadyEarned() throws {
        let context = try makeContext()
        try AchievementBootstrap.bootstrapIfNeeded(context: context)
        let repo = AchievementRepository(context: context)

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        try context.save()

        _ = try repo.awardAchievements(keys: ["first_lesson"], for: user)
        let second = try repo.awardAchievements(keys: ["first_lesson"], for: user)
        #expect(second.isEmpty)

        let earned = try repo.fetchEarnedAchievements(for: user)
        #expect(earned.count == 1)
    }

    @Test func awardSkipsUnknownKeys() throws {
        let context = try makeContext()
        try AchievementBootstrap.bootstrapIfNeeded(context: context)
        let repo = AchievementRepository(context: context)

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        try context.save()

        let awarded = try repo.awardAchievements(keys: ["nonexistent_key"], for: user)
        #expect(awarded.isEmpty)
    }

    @Test func awardOnlyNewKeys() throws {
        let context = try makeContext()
        try AchievementBootstrap.bootstrapIfNeeded(context: context)
        let repo = AchievementRepository(context: context)

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        try context.save()

        _ = try repo.awardAchievements(keys: ["first_lesson"], for: user)
        let second = try repo.awardAchievements(
            keys: ["first_lesson", "xp_100", "streak_7"], for: user
        )
        #expect(second.count == 2)
        let earnedKeys = try Set(repo.fetchEarnedKeys(for: user))
        #expect(earnedKeys == ["first_lesson", "xp_100", "streak_7"])
    }

    // MARK: - Perfect lesson count

    @Test func perfectLessonCountDerivedFromLessonProgress() throws {
        let context = try makeContext()
        try AchievementBootstrap.bootstrapIfNeeded(context: context)
        let repo = AchievementRepository(context: context)

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)

        let course = Course(key: "c", titleKey: "t")
        context.insert(course)
        let level = Level(key: "l", cefr: .a1, orderIndex: 0, course: course)
        context.insert(level)
        let unit = Unit(key: "u", orderIndex: 0, titleKey: "t", theme: "th", summaryKey: "s", level: level)
        context.insert(unit)

        // Two perfect lessons + one imperfect.
        for i in 0..<3 {
            let lesson = Lesson(key: "l\(i)", orderIndex: i, titleKey: "t", kind: .skill, unit: unit)
            context.insert(lesson)
            let progress = LessonProgress(status: .completed, user: user, lesson: lesson)
            progress.bestAccuracy = i == 2 ? 0.5 : 1.0
            context.insert(progress)
        }
        try context.save()

        #expect(try repo.fetchPerfectLessonCount(for: user) == 2)
    }
}
