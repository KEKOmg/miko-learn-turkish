import Foundation
import SwiftData
import Testing
@testable import Miko

/// Tests for the Home / Course Map navigation logic in
/// `LessonProgressRepository`:
/// - `fetchNextUnfinishedLesson` (Home CTA target)
/// - `fetchCourseMap` (locked / unlocked / completed states and adjacency)
/// - `fetchUserStats` (Home stats snapshot)
///
/// These build a synthetic Course → Level → Unit → Lesson graph in an
/// in-memory SwiftData container so the navigation rules can be verified
/// without the UI.
@MainActor
struct LessonNavigationTests {

    typealias LearningUnit = Miko.Unit

    // MARK: - Fixtures

    private struct Fixture {
        let context: ModelContext
        let repository: LessonProgressRepository
        let user: UserProfile
        let course: Course
        let level: Level
        let units: [LearningUnit]
        let lessons: [Lesson] // in course order
    }

    /// Builds a course with one level, two units, two lessons per unit
    /// (4 lessons total, in strict order).
    private func makeFixture() throws -> Fixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)

        let course = Course(key: "course.ru-tr", titleKey: "course.ru-tr.title")
        context.insert(course)

        let level = Level(key: "a1", cefr: .a1, orderIndex: 0, course: course)
        context.insert(level)

        var units: [LearningUnit] = []
        var lessons: [Lesson] = []
        for u in 0..<2 {
            let unit = LearningUnit(
                key: "a1.u\(u + 1)",
                orderIndex: u,
                titleKey: "unit.a1.u\(u + 1).title",
                theme: "theme",
                summaryKey: "unit.a1.u\(u + 1).summary",
                level: level
            )
            context.insert(unit)
            units.append(unit)
            for l in 0..<2 {
                let lessonKey = "a1.u\(u + 1).l\(l + 1)"
                let lesson = Lesson(
                    key: lessonKey,
                    orderIndex: l,
                    titleKey: "lesson.\(lessonKey).title",
                    kind: .skill,
                    unit: unit
                )
                context.insert(lesson)
                lessons.append(lesson)
            }
        }
        try context.save()

        return Fixture(
            context: context,
            repository: LessonProgressRepository(context: context),
            user: user,
            course: course,
            level: level,
            units: units,
            lessons: lessons
        )
    }

    /// Builds a two-level course (A1 and A2, one unit each, two lessons per
    /// unit) to verify gating across level boundaries.
    private func makeTwoLevelFixture() throws -> Fixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)

        let course = Course(key: "course.ru-tr", titleKey: "course.ru-tr.title")
        context.insert(course)

        let a1 = Level(key: "a1", cefr: .a1, orderIndex: 0, course: course)
        context.insert(a1)
        let a2 = Level(key: "a2", cefr: .a2, orderIndex: 1, course: course)
        context.insert(a2)

        var units: [LearningUnit] = []
        var lessons: [Lesson] = []
        for (levelKey, level) in [("a1", a1), ("a2", a2)] {
            let unit = LearningUnit(
                key: "\(levelKey).u1",
                orderIndex: 0,
                titleKey: "unit.\(levelKey).u1.title",
                theme: "theme",
                summaryKey: "unit.\(levelKey).u1.summary",
                level: level
            )
            context.insert(unit)
            units.append(unit)
            for l in 0..<2 {
                let lessonKey = "\(levelKey).u1.l\(l + 1)"
                let lesson = Lesson(
                    key: lessonKey,
                    orderIndex: l,
                    titleKey: "lesson.\(lessonKey).title",
                    kind: .skill,
                    unit: unit
                )
                context.insert(lesson)
                lessons.append(lesson)
            }
        }
        try context.save()

        return Fixture(
            context: context,
            repository: LessonProgressRepository(context: context),
            user: user,
            course: course,
            level: a1,
            units: units,
            lessons: lessons
        )
    }

    /// Marks a lesson completed for the fixture user with the given accuracy.
    private func complete(_ fixture: Fixture, lesson: Lesson, accuracy: Double) throws {
        let progress = LessonProgress(status: .completed, user: fixture.user, lesson: lesson)
        progress.bestAccuracy = accuracy
        fixture.context.insert(progress)
        try fixture.context.save()
    }

    // MARK: - fetchNextUnfinishedLesson

    @Test func nextLessonOnFreshStartIsFirstLesson() throws {
        let fixture = try makeFixture()
        let next = try fixture.repository.fetchNextUnfinishedLesson(courseKey: "course.ru-tr")
        #expect(next?.key == "a1.u1.l1")
    }

    @Test func nextLessonAdvancesAfterFirstCompletion() throws {
        let fixture = try makeFixture()
        try complete(fixture, lesson: fixture.lessons[0], accuracy: 1.0)

        let next = try fixture.repository.fetchNextUnfinishedLesson(courseKey: "course.ru-tr")
        #expect(next?.key == "a1.u1.l2")
    }

    @Test func nextLessonAdvancesAcrossUnitBoundary() throws {
        let fixture = try makeFixture()
        // Complete all of unit 1.
        // Star count is only a quality indicator: even one- and two-star
        // completions must unlock the next CEFR level.
        try complete(fixture, lesson: fixture.lessons[0], accuracy: 0.2)
        try complete(fixture, lesson: fixture.lessons[1], accuracy: 0.7)

        let next = try fixture.repository.fetchNextUnfinishedLesson(courseKey: "course.ru-tr")
        #expect(next?.key == "a1.u2.l1")
    }

    @Test func nextLessonWhenAllCompletedReturnsNil() throws {
        let fixture = try makeFixture()
        for lesson in fixture.lessons {
            try complete(fixture, lesson: lesson, accuracy: 1.0)
        }

        let next = try fixture.repository.fetchNextUnfinishedLesson(courseKey: "course.ru-tr")
        #expect(next == nil)
    }

    @Test func nextLessonReturnsNilForUnknownCourse() throws {
        let fixture = try makeFixture()
        let next = try fixture.repository.fetchNextUnfinishedLesson(courseKey: "course.unknown")
        #expect(next == nil)
    }

    // MARK: - fetchCourseMap: locked / unlocked / completed

    @Test func courseMapFirstLessonUnlockedRestLockedOnFreshStart() throws {
        let fixture = try makeFixture()
        let snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")

        let lessons = snapshot?.allLessons ?? []
        #expect(lessons.count == 4)
        #expect(lessons[0].state == .unlocked)
        #expect(lessons[1].state == .locked)
        #expect(lessons[2].state == .locked)
        #expect(lessons[3].state == .locked)
    }

    @Test func courseMapUnlocksNextLessonAfterCompletion() throws {
        let fixture = try makeFixture()
        try complete(fixture, lesson: fixture.lessons[0], accuracy: 1.0)

        let snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        let lessons = snapshot?.allLessons ?? []

        #expect(lessons[0].state == .completed(stars: 3, accuracy: 1.0))
        #expect(lessons[1].state == .unlocked)
        #expect(lessons[2].state == .locked)
        #expect(lessons[3].state == .locked)
    }

    @Test func courseMapUnlocksFirstLessonOfNextUnitWhenPreviousUnitDone() throws {
        let fixture = try makeFixture()
        try complete(fixture, lesson: fixture.lessons[0], accuracy: 0.7)
        try complete(fixture, lesson: fixture.lessons[1], accuracy: 0.7)

        let snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        let lessons = snapshot?.allLessons ?? []

        // Unit 1 fully completed (2 stars each, since 0.7 → 2 stars).
        if case .completed(let stars0, _) = lessons[0].state { #expect(stars0 == 2) } else { Issue.record("expected completed") }
        if case .completed(let stars1, _) = lessons[1].state { #expect(stars1 == 2) } else { Issue.record("expected completed") }
        // Unit 2 first lesson unlocked by adjacency to the last lesson of unit 1.
        #expect(lessons[2].state == .unlocked)
        #expect(lessons[3].state == .locked)
    }

    @Test func courseMapCompletedLessonsRemainPlayable() throws {
        let fixture = try makeFixture()
        try complete(fixture, lesson: fixture.lessons[0], accuracy: 1.0)

        let snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        let first = snapshot?.allLessons.first
        #expect(first?.isPlayable == true)
    }

    @Test func courseMapLockedLessonsAreNotPlayable() throws {
        let fixture = try makeFixture()
        let snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        let locked = snapshot?.allLessons.dropFirst() ?? []
        #expect(locked.allSatisfy { $0.isPlayable == false })
    }

    @Test func courseMapStarsReflectBestAccuracy() throws {
        let fixture = try makeFixture()
        // 0.5 accuracy → 1 star.
        try complete(fixture, lesson: fixture.lessons[0], accuracy: 0.5)

        let snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        if case .completed(let stars, let acc) = snapshot?.allLessons.first?.state {
            #expect(stars == 1)
            #expect(abs(acc - 0.5) < 0.0001)
        } else {
            Issue.record("Expected completed state")
        }
    }

    @Test func courseMapReturnsNilForUnknownCourse() throws {
        let fixture = try makeFixture()
        let snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.unknown")
        #expect(snapshot == nil)
    }

    @Test func courseMapUnitProgressCountIsCorrect() throws {
        let fixture = try makeFixture()
        try complete(fixture, lesson: fixture.lessons[0], accuracy: 1.0)

        let snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        let firstUnit = snapshot?.levels.first?.units.first
        #expect(firstUnit?.completedCount == 1)
        #expect(firstUnit?.lessons.count == 2)
    }

    // MARK: - Cross-level gating (A2 after A1)

    @Test func firstLessonOfSecondLevelLockedUntilPreviousLevelDone() throws {
        let fixture = try makeTwoLevelFixture()
        var snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        var lessons = snapshot?.allLessons ?? []
        #expect(lessons.count == 4)
        #expect(lessons[2].state == .locked, "A2.u1.l1 must start locked")

        try complete(fixture, lesson: fixture.lessons[0], accuracy: 1.0)
        snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        lessons = snapshot?.allLessons ?? []
        #expect(lessons[1].state == .unlocked)
        #expect(lessons[2].state == .locked, "A2.u1.l1 stays locked until ALL of A1 is done")

        try complete(fixture, lesson: fixture.lessons[1], accuracy: 1.0)
        snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        lessons = snapshot?.allLessons ?? []
        #expect(lessons[2].state == .unlocked, "A2.u1.l1 unlocks after A1 completion")
        #expect(lessons[3].state == .locked)
    }

    @Test func nextLessonAdvancesAcrossLevelBoundary() throws {
        let fixture = try makeTwoLevelFixture()
        try complete(fixture, lesson: fixture.lessons[0], accuracy: 1.0)
        try complete(fixture, lesson: fixture.lessons[1], accuracy: 1.0)

        let next = try fixture.repository.fetchNextUnfinishedLesson(courseKey: "course.ru-tr")
        #expect(next?.key == "a2.u1.l1")
    }

    @Test func courseMapSuggestsA1UntilItIsCompletedThenA2() throws {
        let fixture = try makeTwoLevelFixture()

        var snapshot = try #require(
            try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        )
        #expect(snapshot.suggestedLevelKey == "a1")
        #expect(snapshot.levels[0].isAvailable)
        #expect(!snapshot.levels[0].isCompleted)
        #expect(!snapshot.levels[1].isAvailable)

        try complete(fixture, lesson: fixture.lessons[0], accuracy: 1.0)
        try complete(fixture, lesson: fixture.lessons[1], accuracy: 1.0)

        snapshot = try #require(
            try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        )
        #expect(snapshot.suggestedLevelKey == "a2")
        #expect(snapshot.levels[0].isCompleted)
        #expect(snapshot.levels[1].isAvailable)
    }

    // MARK: - fetchUserStats

    @Test func userStatsReturnsDefaultsWhenNoProgress() throws {
        let fixture = try makeFixture()
        let stats = try fixture.repository.fetchUserStats()

        #expect(stats != nil)
        #expect(stats?.xp == 0)
        #expect(stats?.streakDays == 0)
        #expect(stats?.heartsTotal == LessonProgressRepository.placeholderHeartsTotal)
        #expect(stats?.heartsRemaining == LessonProgressRepository.placeholderHeartsTotal)
        #expect(stats?.dailyGoalProgress == 0)
    }

    @Test func userStatsReflectsProgress() throws {
        let fixture = try makeFixture()
        let progress = UserProgress()
        progress.xp = 120
        progress.user = fixture.user
        fixture.context.insert(progress)

        let streak = Streak(currentStreak: 7)
        streak.user = fixture.user
        progress.streak = streak
        fixture.context.insert(streak)

        let goal = DailyGoal(xpTarget: 50, xpEarnedToday: 30)
        goal.user = fixture.user
        progress.dailyGoal = goal
        fixture.context.insert(goal)
        try fixture.context.save()

        let stats = try fixture.repository.fetchUserStats()
        #expect(stats?.xp == 120)
        #expect(stats?.streakDays == 7)
        #expect(stats?.dailyGoalXP == 50)
        #expect(stats?.dailyGoalEarned == 30)
        #expect(abs((stats?.dailyGoalProgress ?? 0) - 0.6) < 0.0001)
        #expect(stats?.isDailyGoalReached == false)
    }

    @Test func userStatsDailyGoalReachedWhenEarnedAtOrAboveTarget() throws {
        let fixture = try makeFixture()
        let progress = UserProgress()
        progress.user = fixture.user
        fixture.context.insert(progress)

        let goal = DailyGoal(xpTarget: 50, xpEarnedToday: 50)
        goal.user = fixture.user
        progress.dailyGoal = goal
        fixture.context.insert(goal)
        try fixture.context.save()

        let stats = try fixture.repository.fetchUserStats()
        #expect(stats?.isDailyGoalReached == true)
    }

    // MARK: - stars helper

    @Test func starsMappingMatchesResultsView() {
        #expect(LessonProgressRepository.stars(forAccuracy: 0.9) == 3)
        #expect(LessonProgressRepository.stars(forAccuracy: 0.95) == 3)
        #expect(LessonProgressRepository.stars(forAccuracy: 0.6) == 2)
        #expect(LessonProgressRepository.stars(forAccuracy: 0.75) == 2)
        #expect(LessonProgressRepository.stars(forAccuracy: 0.59) == 1)
        #expect(LessonProgressRepository.stars(forAccuracy: 0.0) == 1)
    }

    // MARK: - User isolation (predicate-based filtering)

    /// Another user's completion records must not leak into the primary
    /// user's `fetchNextUnfinishedLesson` / `fetchCourseMap` results. This
    /// guards the predicate refactor that moved user filtering from Swift
    /// into the `#Predicate`.
    @Test func otherUserCompletionsDoNotLeakIntoPrimaryUserView() throws {
        let fixture = try makeFixture()
        // Insert a second user and mark lesson[0] completed for them only.
        let otherUser = UserProfile(username: "other", avatar: "")
        fixture.context.insert(otherUser)
        let otherProgress = LessonProgress(status: .completed, user: otherUser, lesson: fixture.lessons[0])
        otherProgress.bestAccuracy = 1.0
        fixture.context.insert(otherProgress)
        try fixture.context.save()

        // Primary user (inserted first in `makeFixture`) has no completions,
        // so the next unfinished lesson is the first lesson — not lesson[1].
        let next = try fixture.repository.fetchNextUnfinishedLesson(courseKey: "course.ru-tr")
        #expect(next?.key == "a1.u1.l1")

        // The course map must show lesson[0] as unlocked (entry point), not
        // completed — the other user's completion must not appear here.
        let snapshot = try fixture.repository.fetchCourseMap(courseKey: "course.ru-tr")
        let lessons = snapshot?.allLessons ?? []
        #expect(lessons[0].state == .unlocked)
        #expect(lessons[1].state == .locked)
    }
}
