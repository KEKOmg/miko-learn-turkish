import Foundation
import SwiftData
import Testing
@testable import Miko

/// Tests for restoring progress from the cloud profile row: pure merging,
/// applying merged values to the local store, and decoding the REST payload.
struct ProgressRestoreTests {

    // MARK: - Merging

    @Test func mergeAdoptsCloudWhenLocalMissing() {
        let cloud = CloudProgress(username: "Vlad", xp: 120, streakDays: 4, lessonsCompleted: 7)
        let merged = ProgressRestoreService.merge(local: nil, cloud: cloud)
        #expect(merged == cloud)
    }

    @Test func mergeTakesMaxPerField() {
        let local = CloudProgress(username: "Vlad", xp: 300, streakDays: 1, lessonsCompleted: 5)
        let cloud = CloudProgress(username: "Vlad", xp: 120, streakDays: 9, lessonsCompleted: 3)
        let merged = ProgressRestoreService.merge(local: local, cloud: cloud)

        #expect(merged.xp == 300)
        #expect(merged.streakDays == 9)
        #expect(merged.lessonsCompleted == 5)
    }

    @Test func mergeKeepsCloudUsername() {
        let local = CloudProgress(username: "", xp: 0, streakDays: 0, lessonsCompleted: 0)
        let cloud = CloudProgress(username: "Ayşe", xp: 0, streakDays: 0, lessonsCompleted: 0)
        #expect(ProgressRestoreService.merge(local: local, cloud: cloud).username == "Ayşe")
    }

    // MARK: - Applying to the store

    @MainActor
    @Test func applyRaisesLocalCountersToCloudValues() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let user = try makeFixture(into: context)
        user.progress?.xp = 50
        user.progress?.totalLessonsCompleted = 2
        user.progress?.streak?.currentStreak = 1

        let cloud = CloudProgress(username: "", xp: 240, streakDays: 6, lessonsCompleted: 10)
        let didChange = try ProgressRestoreService.apply(cloud, context: context)

        #expect(didChange)
        #expect(user.progress?.xp == 240)
        #expect(user.progress?.totalLessonsCompleted == 10)
        #expect(user.progress?.streak?.currentStreak == 6)
        #expect(user.progress?.streak?.longestStreak == 6)
        // An adopted streak claims today so the next session keeps it alive.
        #expect(
            Calendar.current.isDateInToday(user.progress?.streak?.lastActiveDate ?? .distantPast)
        )
    }

    @MainActor
    @Test func applyNeverLowersLocalProgress() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let user = try makeFixture(into: context)
        user.progress?.xp = 500
        user.progress?.totalLessonsCompleted = 12
        user.progress?.streak?.currentStreak = 8
        user.progress?.streak?.longestStreak = 20

        let cloud = CloudProgress(username: "", xp: 100, streakDays: 2, lessonsCompleted: 4)
        let didChange = try ProgressRestoreService.apply(cloud, context: context)

        #expect(!didChange)
        #expect(user.progress?.xp == 500)
        #expect(user.progress?.totalLessonsCompleted == 12)
        #expect(user.progress?.streak?.currentStreak == 8)
        #expect(user.progress?.streak?.longestStreak == 20)
    }

    @MainActor
    @Test func applyFillsEmptyUsernameFromCloud() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let user = try makeFixture(into: context)

        let cloud = CloudProgress(username: "Zeynep", xp: 0, streakDays: 0, lessonsCompleted: 0)
        _ = try ProgressRestoreService.apply(cloud, context: context)

        #expect(user.username == "Zeynep")
    }

    // MARK: - Payload decoding

    @Test func profileRowDecodesSnakeCase() throws {
        let json = """
        {"username":"Mehmet","xp":77,"streak_days":3,"lessons_completed":9}
        """
        let row = try JSONDecoder().decode(SupabaseAuthClient.ProfileRow.self, from: Data(json.utf8))
        #expect(row.username == "Mehmet")
        #expect(row.xp == 77)
        #expect(row.streakDays == 3)
        #expect(row.lessonsCompleted == 9)

        let progress = row.progress
        #expect(progress.xp == 77)
        #expect(progress.streakDays == 3)
    }

    @Test func lessonProgressRowDecodesStableKeyAndTimestamp() throws {
        let json = """
        {"lesson_key":"a1.u1.l1","best_accuracy":0.875,"completed_at":"2026-09-05T08:12:34.123Z"}
        """
        let row = try JSONDecoder().decode(
            SupabaseAuthClient.LessonProgressRow.self,
            from: Data(json.utf8)
        )
        let progress = try #require(row.progress)
        #expect(progress.lessonKey == "a1.u1.l1")
        #expect(progress.bestAccuracy == 0.875)
    }

    // MARK: - Account isolation

    @MainActor
    @Test func guestAndAuthenticatedAccountsUseIndependentProfileGraphs() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let suiteName = "ProgressRestoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let guest = try UserBootstrap.bootstrapIfNeeded(context: context, defaults: defaults)
        guest.progress?.xp = 90

        let accountAID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let accountBID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let accountA = try UserBootstrap.accountProfile(
            id: accountAID,
            username: "A",
            context: context
        )
        let accountB = try UserBootstrap.accountProfile(
            id: accountBID,
            username: "B",
            context: context
        )
        accountA.progress?.xp = 40
        accountB.progress?.xp = 7
        try context.save()

        let a = try LessonProgressRepository(
            context: context,
            profileID: accountAID
        ).fetchPrimaryUserProfile()
        let b = try LessonProgressRepository(
            context: context,
            profileID: accountBID
        ).fetchPrimaryUserProfile()
        let guestAfterLogout = try UserBootstrap.bootstrapIfNeeded(
            context: context,
            defaults: defaults
        )

        #expect(a?.id == accountAID)
        #expect(a?.progress?.xp == 40)
        #expect(b?.id == accountBID)
        #expect(b?.progress?.xp == 7)
        #expect(guestAfterLogout.id == guest.id)
        #expect(guestAfterLogout.progress?.xp == 90)
        #expect(Set([guest.id, accountA.id, accountB.id]).count == 3)
    }

    @MainActor
    @Test func aggregateRestoreMutatesOnlyItsOwner() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let accountAID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let accountBID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let accountA = try UserBootstrap.accountProfile(id: accountAID, username: "A", context: context)
        let accountB = try UserBootstrap.accountProfile(id: accountBID, username: "B", context: context)
        accountA.progress?.xp = 10
        accountB.progress?.xp = 20

        _ = try ProgressRestoreService.apply(
            CloudProgress(username: "A", xp: 300, streakDays: 5, lessonsCompleted: 8),
            context: context,
            profileID: accountAID
        )

        #expect(accountA.progress?.xp == 300)
        #expect(accountA.progress?.totalLessonsCompleted == 8)
        #expect(accountB.progress?.xp == 20)
        #expect(accountB.progress?.totalLessonsCompleted == 0)
    }

    @MainActor
    @Test func completedLessonHydrationIsOwnerScopedAndRewardFree() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let fixture = try makeTwoLevelCourse(into: context)
        let accountAID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let accountBID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let accountA = try UserBootstrap.accountProfile(id: accountAID, username: "A", context: context)
        let accountB = try UserBootstrap.accountProfile(id: accountBID, username: "B", context: context)
        accountA.progress?.xp = 130
        accountA.progress?.totalLessonsCompleted = 9
        accountB.progress?.xp = 20

        let rows = [CloudLessonProgress(
            lessonKey: fixture.lessons[0].key,
            bestAccuracy: 0.75,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )]
        #expect(try ProgressRestoreService.hydrateLessonProgress(
            rows,
            context: context,
            profileID: accountAID
        ) == 1)

        let aMap = try LessonProgressRepository(
            context: context,
            profileID: accountAID
        ).fetchCourseMap(courseKey: "course.ru-tr")
        let bMap = try LessonProgressRepository(
            context: context,
            profileID: accountBID
        ).fetchCourseMap(courseKey: "course.ru-tr")

        if case .completed = aMap?.allLessons.first?.state {} else {
            Issue.record("A's hydrated lesson must be completed")
        }
        #expect(bMap?.allLessons.first?.state == .unlocked)
        #expect(accountA.progress?.xp == 130)
        #expect(accountA.progress?.totalLessonsCompleted == 9)
        #expect(accountB.progress?.xp == 20)
        #expect(try ProgressRestoreService.hydrateLessonProgress(
            rows,
            context: context,
            profileID: accountAID
        ) == 0, "Hydration must be idempotent")
    }

    @MainActor
    @Test func cleanInstallHydrationRestoresA1AndUnlocksA2WithoutXP() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let fixture = try makeTwoLevelCourse(into: context)
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let account = try UserBootstrap.accountProfile(id: accountID, username: "A", context: context)
        account.progress?.xp = 500
        account.progress?.totalLessonsCompleted = 2

        let cloudRows = fixture.lessons.prefix(2).map {
            CloudLessonProgress(
                lessonKey: $0.key,
                bestAccuracy: 1,
                completedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }
        #expect(try ProgressRestoreService.hydrateLessonProgress(
            cloudRows,
            context: context,
            profileID: accountID
        ) == 2)

        let restoredMap = try LessonProgressRepository(
            context: context,
            profileID: accountID
        ).fetchCourseMap(courseKey: "course.ru-tr")
        let snapshot = try #require(restoredMap)
        #expect(snapshot.levels[0].isCompleted)
        #expect(snapshot.levels[1].isAvailable)
        #expect(snapshot.suggestedLevelKey == "a2")
        #expect(snapshot.allLessons[2].state == .unlocked)
        #expect(account.progress?.xp == 500)
        #expect(account.progress?.totalLessonsCompleted == 2)
    }

    // MARK: - Fixture

    @MainActor
    @Test func unscopedRepositoriesRejectAmbiguousAccountOwner() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try UserBootstrap.accountProfile(id: UUID(), username: "A", context: context)
        try UserBootstrap.accountProfile(id: UUID(), username: "B", context: context)
        #expect(try GamificationRepository(context: context).fetchPrimaryUserProfile() == nil)
        #expect(try LessonProgressRepository(context: context).fetchPrimaryUserProfile() == nil)
        #expect(ProgressRestoreService.currentLocalProgress(context: context) == nil)
    }

    @MainActor
    @Test func fullBundledA1RestoresIntoFreshStoreWithoutRewards() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let accountID = UUID()
        let original = try ContentTestSupport.makeInMemoryContainer()
        try ContentImporter.import(bundle, into: original.mainContext)
        let account = try UserBootstrap.accountProfile(
            id: accountID, username: "A", context: original.mainContext
        )
        let a1Lessons = try original.mainContext.fetch(FetchDescriptor<Lesson>())
            .filter { $0.key.hasPrefix("a1.") }
        #expect(!a1Lessons.isEmpty)
        let rows = a1Lessons.map {
            CloudLessonProgress(lessonKey: $0.key, bestAccuracy: 1, completedAt: .now)
        }
        let cloud = CloudProgress(username: "A", xp: 500, streakDays: 2, lessonsCompleted: rows.count)
        try ProgressRestoreService.apply(cloud, context: original.mainContext, profileID: accountID)
        try ProgressRestoreService.hydrateLessonProgress(rows, context: original.mainContext, profileID: accountID)
        let uploaded = try ProgressRestoreService.currentLocalLessonProgress(
            context: original.mainContext, profileID: accountID
        )

        // New container imports the bundle again: local model UUIDs change,
        // so only stable lesson keys can restore the completed course.
        let fresh = try ContentTestSupport.makeInMemoryContainer()
        try ContentImporter.import(bundle, into: fresh.mainContext)
        let restored = try UserBootstrap.accountProfile(
            id: accountID, username: "A", context: fresh.mainContext
        )
        try ProgressRestoreService.apply(cloud, context: fresh.mainContext, profileID: accountID)
        try ProgressRestoreService.hydrateLessonProgress(uploaded, context: fresh.mainContext, profileID: accountID)
        let repository = LessonProgressRepository(context: fresh.mainContext, profileID: accountID)
        let restoredMap = try repository.fetchCourseMap(courseKey: "course.ru-tr")
        let map = try #require(restoredMap)
        #expect(map.levels.first(where: { $0.key == "a1" })?.isCompleted == true)
        #expect(map.levels.first(where: { $0.key == "a2" })?.isAvailable == true)
        #expect(map.suggestedLevelKey == "a2")
        #expect(restored.progress?.xp == account.progress?.xp)
        #expect(restored.progress?.xp == 500)
        #expect(restored.progress?.dailyGoal?.xpEarnedToday == 0)
        #expect(try repository.fetchCompletedLessonProgress(user: restored).count == rows.count)
    }

    @MainActor
    @Test func missingGuestRowDoesNotAdoptCachedAccount() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let suiteName = "MikoTests.guest-recovery.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let guestID = UUID()
        defaults.set(guestID.uuidString, forKey: "localProfile.guestID")
        let account = try UserBootstrap.accountProfile(id: UUID(), username: "A", context: context)
        account.progress?.xp = 130

        let guest = try UserBootstrap.bootstrapIfNeeded(context: context, defaults: defaults)
        #expect(guest.id == guestID)
        #expect(guest.id != account.id)
        #expect(guest.progress?.xp == 0)
        #expect(account.progress?.xp == 130)
    }

    @MainActor
    private func makeFixture(into context: ModelContext) throws -> UserProfile {
        let user = UserProfile(username: "", avatar: "")
        context.insert(user)
        let progress = UserProgress()
        progress.user = user
        context.insert(progress)
        let streak = Streak(user: user)
        progress.streak = streak
        context.insert(streak)
        try context.save()
        return user
    }

    @MainActor
    private func makeTwoLevelCourse(
        into context: ModelContext
    ) throws -> (course: Course, lessons: [Lesson]) {
        let course = Course(key: "course.ru-tr", titleKey: "course.ru-tr.title")
        context.insert(course)
        var lessons: [Lesson] = []
        for (levelIndex, levelKey) in ["a1", "a2"].enumerated() {
            let level = Level(
                key: levelKey,
                cefr: levelKey == "a1" ? .a1 : .a2,
                orderIndex: levelIndex,
                course: course
            )
            context.insert(level)
            let unit = Miko.Unit(
                key: "\(levelKey).u1",
                orderIndex: 0,
                titleKey: "unit.\(levelKey).u1.title",
                theme: "test",
                summaryKey: "unit.\(levelKey).u1.summary",
                level: level
            )
            context.insert(unit)
            for lessonIndex in 0..<2 {
                let key = "\(levelKey).u1.l\(lessonIndex + 1)"
                let lesson = Lesson(
                    key: key,
                    orderIndex: lessonIndex,
                    titleKey: "lesson.\(key).title",
                    kind: .skill,
                    unit: unit
                )
                context.insert(lesson)
                lessons.append(lesson)
            }
        }
        try context.save()
        return (course, lessons)
    }
}
