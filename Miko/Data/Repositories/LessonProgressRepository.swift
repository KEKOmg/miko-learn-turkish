import Foundation
import SwiftData

/// Owns all lesson-progress persistence: loading playable lessons and
/// recording lesson/exercise completion. Centralized here so neither the
/// ViewModel nor SwiftUI views perform raw SwiftData mutations.
struct LessonProgressRepository {
    private let context: ModelContext
    private let profileID: UUID?

    init(context: ModelContext, profileID: UUID? = nil) {
        self.context = context
        self.profileID = profileID
    }

    // MARK: - Fetching

    func fetchLesson(id: UUID) throws -> Lesson? {
        let predicate = #Predicate<Lesson> { $0.id == id }
        var descriptor = FetchDescriptor<Lesson>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchExercises(for lesson: Lesson) throws -> [Exercise] {
        lesson.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// The first playable lesson of the seeded course, following the
    /// Course → Level → Unit → Lesson order.
    func fetchFirstLesson(courseKey: String) throws -> Lesson? {
        let predicate = #Predicate<Course> { $0.key == courseKey }
        var descriptor = FetchDescriptor<Course>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let course = try context.fetch(descriptor).first else { return nil }

        let levels = course.levels.sorted { $0.orderIndex < $1.orderIndex }
        for level in levels {
            let units = level.units.sorted { $0.orderIndex < $1.orderIndex }
            for unit in units {
                let lessons = unit.lessons.sorted { $0.orderIndex < $1.orderIndex }
                if let first = lessons.first { return first }
            }
        }
        return nil
    }

    func fetchPrimaryUserProfile() throws -> UserProfile? {
        if let profileID {
            let predicate = #Predicate<UserProfile> { $0.id == profileID }
            var descriptor = FetchDescriptor<UserProfile>(predicate: predicate)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
        }
        // Fail closed when the caller omitted an owner in a multi-user store.
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 2
        let profiles = try context.fetch(descriptor)
        return profiles.count == 1 ? profiles[0] : nil
    }

    /// Stable-key snapshots used for cloud union sync. Content UUIDs are
    /// generated per install, so only `Lesson.key` may cross devices.
    func fetchCompletedLessonProgress(user: UserProfile) throws -> [CloudLessonProgress] {
        let userID = user.id
        let predicate = #Predicate<LessonProgress> {
            $0.statusRaw == "completed" && $0.user?.id == userID
        }
        return try context.fetch(FetchDescriptor<LessonProgress>(predicate: predicate))
            .compactMap { progress in
                guard let lessonKey = progress.lesson?.key else { return nil }
                return CloudLessonProgress(
                    lessonKey: lessonKey,
                    bestAccuracy: progress.bestAccuracy,
                    completedAt: progress.lastCompletedAt ?? Date(timeIntervalSince1970: 0)
                )
            }
            .sorted { $0.lessonKey < $1.lessonKey }
    }

    /// Hydrates completed lesson rows without invoking gamification or reward
    /// logic. Returns the number of local rows that were created or raised.
    @discardableResult
    func hydrateCompletedLessons(
        _ cloudRows: [CloudLessonProgress],
        user: UserProfile
    ) throws -> Int {
        let lessonsByKey = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Lesson>()).map { ($0.key, $0) }
        )
        var changed = 0

        for cloud in cloudRows {
            guard let lesson = lessonsByKey[cloud.lessonKey] else { continue }
            let progress = try fetchOrCreateLessonProgress(user: user, lesson: lesson)
            var didChange = false
            if progress.status != .completed {
                progress.status = .completed
                didChange = true
            }
            if cloud.bestAccuracy > progress.bestAccuracy {
                progress.bestAccuracy = min(1, max(0, cloud.bestAccuracy))
                didChange = true
            }
            if progress.attempts == 0 {
                progress.attempts = 1
                didChange = true
            }
            if cloud.completedAt > (progress.lastCompletedAt ?? .distantPast) {
                progress.lastCompletedAt = cloud.completedAt
                didChange = true
            }
            if didChange { changed += 1 }
        }

        if changed > 0 { try context.save() }
        return changed
    }

    // MARK: - Navigation

    /// Returns the next lesson the user should play: the first lesson in
    /// course order that has not been completed yet. Falls back to the first
    /// lesson when nothing has been completed (fresh start), and to `nil`
    /// when every lesson is completed.
    func fetchNextUnfinishedLesson(courseKey: String) throws -> Lesson? {
        guard let ordered = try fetchOrderedLessons(courseKey: courseKey) else { return nil }
        guard let user = try fetchPrimaryUserProfile() else {
            // No profile yet — surface the first lesson so the Home CTA works
            // during the very first launch before UserBootstrap has run.
            return ordered.first
        }
        let completedIDs = try fetchCompletedLessonIDs(user: user)

        let next = ordered.first { lesson in
            !completedIDs.contains(lesson.id)
        }
        return next
    }

    /// Builds a full ordered snapshot of the course with each lesson's
    /// computed state. Used by the Course Map.
    func fetchCourseMap(courseKey: String) throws -> CourseMapSnapshot? {
        let predicate = #Predicate<Course> { $0.key == courseKey }
        var descriptor = FetchDescriptor<Course>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let course = try context.fetch(descriptor).first else { return nil }

        let user = try fetchPrimaryUserProfile()
        let completedByID: [UUID: LessonProgress]
        if let user {
            completedByID = (try? fetchCompletedLessonsByID(user: user)) ?? [:]
        } else {
            completedByID = [:]
        }

        let levels = course.levels.sorted { $0.orderIndex < $1.orderIndex }
        let levelSections: [LevelSection] = levels.map { level in
            let units = level.units.sorted { $0.orderIndex < $1.orderIndex }
            let unitSections: [UnitSection] = units.map { unit in
                let lessons = unit.lessons.sorted { $0.orderIndex < $1.orderIndex }
                let nodes = lessons.enumerated().map { index, lesson -> LessonNode in
                    LessonNode(
                        id: lesson.id,
                        key: lesson.key,
                        titleKey: lesson.titleKey,
                        orderIndex: lesson.orderIndex,
                        state: lessonState(
                            for: lesson,
                            unit: unit,
                            indexInUnit: index,
                            completedByID: completedByID
                        )
                    )
                }
                return UnitSection(
                    id: unit.id,
                    key: unit.key,
                    titleKey: unit.titleKey,
                    summaryKey: unit.summaryKey,
                    theme: unit.theme,
                    orderIndex: unit.orderIndex,
                    lessons: nodes
                )
            }
            return LevelSection(
                id: level.id,
                key: level.key,
                cefrRaw: level.cefrRaw,
                orderIndex: level.orderIndex,
                units: unitSections
            )
        }
        return CourseMapSnapshot(courseKey: course.key, levels: levelSections)
    }

    /// Aggregates the user's stats for the Home screen. Returns `nil` when
    /// there is no profile yet (e.g. bootstrap has not completed). Hearts are
    /// read from the persistent `Hearts` row (with lazy regeneration applied)
    /// and fall back to the placeholder constants only when no row exists.
    func fetchUserStats() throws -> UserStatsSnapshot? {
        guard let user = try fetchPrimaryUserProfile(),
              let progress = user.progress else {
            return UserStatsSnapshot(
                xp: 0,
                streakDays: 0,
                heartsTotal: HeartsRepository.defaultMaxHearts,
                heartsRemaining: HeartsRepository.defaultMaxHearts,
                dailyGoalXP: Self.defaultDailyGoalXP,
                dailyGoalEarned: 0
            )
        }
        let streak = user.progress?.streak?.currentStreak ?? 0
        let dailyGoal = user.progress?.dailyGoal
        let dailyGoalXP = dailyGoal?.xpTarget ?? Self.defaultDailyGoalXP
        let dailyGoalEarned = dailyGoal?.xpEarnedToday ?? 0

        // Hearts: regenerate lazily before reading so the UI reflects any
        // time-elapsed refill. Falls back to defaults when no row exists.
        let heartsRepo = HeartsRepository(context: context)
        _ = try? heartsRepo.regenerateIfNeeded(for: user)
        let hearts = try heartsRepo.fetchHearts(for: user)
        let heartsTotal = hearts?.maxHearts ?? HeartsRepository.defaultMaxHearts
        let heartsRemaining = hearts?.currentHearts ?? HeartsRepository.defaultMaxHearts

        return UserStatsSnapshot(
            xp: progress.xp,
            streakDays: streak,
            heartsTotal: heartsTotal,
            heartsRemaining: heartsRemaining,
            dailyGoalXP: dailyGoalXP,
            dailyGoalEarned: dailyGoalEarned
        )
    }

    /// Placeholder heart economy kept for backward compatibility with tests
    /// that reference it directly. Production code reads hearts from the
    /// `Hearts` model via `HeartsRepository`.
    static let placeholderHeartsTotal = HeartsRepository.defaultMaxHearts
    static let defaultDailyGoalXP = 50

    // MARK: - Helpers

    /// Returns lessons in strict course order: level → unit → lesson.
    private func fetchOrderedLessons(courseKey: String) throws -> [Lesson]? {
        let predicate = #Predicate<Course> { $0.key == courseKey }
        var descriptor = FetchDescriptor<Course>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let course = try context.fetch(descriptor).first else { return nil }

        var ordered: [Lesson] = []
        for level in course.levels.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            for unit in level.units.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                ordered.append(contentsOf: unit.lessons.sorted { $0.orderIndex < $1.orderIndex })
            }
        }
        return ordered
    }

    /// Maps `LessonProgress` (status == .completed) for the user to lesson IDs.
    /// User filtering is folded into the `#Predicate` so SwiftData does the
    /// filtering at the store level instead of fetching all rows and filtering
    /// in Swift.
    private func fetchCompletedLessonIDs(user: UserProfile) throws -> Set<UUID> {
        let userID = user.id
        let predicate = #Predicate<LessonProgress> {
            $0.statusRaw == "completed" && $0.user?.id == userID
        }
        let progresses = try context.fetch(FetchDescriptor<LessonProgress>(predicate: predicate))
        return Set(progresses.compactMap { $0.lesson?.id })
    }

    /// Maps `LessonProgress` (status == .completed) for the user to lesson ID
    /// → progress, for star/accuracy lookups. User filtering is folded into
    /// the `#Predicate` (see `fetchCompletedLessonIDs`).
    private func fetchCompletedLessonsByID(user: UserProfile) throws -> [UUID: LessonProgress] {
        let userID = user.id
        let predicate = #Predicate<LessonProgress> {
            $0.statusRaw == "completed" && $0.user?.id == userID
        }
        let progresses = try context.fetch(FetchDescriptor<LessonProgress>(predicate: predicate))
        var map: [UUID: LessonProgress] = [:]
        for p in progresses {
            if let lessonID = p.lesson?.id { map[lessonID] = p }
        }
        return map
    }

    /// Computes a lesson's state from completion records and adjacency.
    ///
    /// Rules:
    /// - Completed if a `LessonProgress` with status `.completed` exists.
    /// - Unlocked if it is the course entry point (first lesson of the first
    ///   unit of the first level), or — when it is the first lesson of its
    ///   unit — the last lesson of the previous unit is completed, or — when
    ///   it is not the first lesson of its unit — the immediately preceding
    ///   lesson in the same unit is completed.
    /// - Locked otherwise.
    private func lessonState(
        for lesson: Lesson,
        unit: Unit,
        indexInUnit: Int,
        completedByID: [UUID: LessonProgress]
    ) -> LessonState {
        if let progress = completedByID[lesson.id] {
            return .completed(
                stars: Self.stars(forAccuracy: progress.bestAccuracy),
                accuracy: progress.bestAccuracy
            )
        }
        if isEntryPoint(unit: unit, indexInUnit: indexInUnit) {
            return .unlocked
        }
        if indexInUnit == 0 {
            // First lesson of a non-first unit: gated by the last lesson of
            // the previous unit (in level order).
            if let lastOfPreviousUnit = lastLessonOfPreviousUnit(unit: unit),
               completedByID[lastOfPreviousUnit.id] != nil {
                return .unlocked
            }
        } else {
            // Non-first lesson: gated by the immediately preceding lesson in
            // the same unit.
            if let previous = previousLesson(unit: unit, indexInUnit: indexInUnit),
               completedByID[previous.id] != nil {
                return .unlocked
            }
        }
        return .locked
    }

    private func isEntryPoint(unit: Unit, indexInUnit: Int) -> Bool {
        guard indexInUnit == 0 else { return false }
        // First unit of its level…
        guard let level = unit.level else { return false }
        let sortedUnits = level.units.sorted { $0.orderIndex < $1.orderIndex }
        guard sortedUnits.first?.id == unit.id else { return false }
        // …and first level of the course.
        guard let course = level.course else { return false }
        let sortedLevels = course.levels.sorted { $0.orderIndex < $1.orderIndex }
        return sortedLevels.first?.id == level.id
    }

    private func previousLesson(unit: Unit, indexInUnit: Int) -> Lesson? {
        guard indexInUnit > 0 else { return nil }
        let sorted = unit.lessons.sorted { $0.orderIndex < $1.orderIndex }
        guard sorted.indices.contains(indexInUnit - 1) else { return nil }
        return sorted[indexInUnit - 1]
    }

    private func lastLessonOfPreviousUnit(unit: Unit) -> Lesson? {
        guard let level = unit.level else { return nil }
        let sortedUnits = level.units.sorted { $0.orderIndex < $1.orderIndex }
        if let unitIndex = sortedUnits.firstIndex(where: { $0.id == unit.id }),
           unitIndex > 0 {
            let previousUnit = sortedUnits[unitIndex - 1]
            return previousUnit.lessons.sorted { $0.orderIndex < $1.orderIndex }.last
        }

        // First unit of its level: gate on the last lesson of the previous
        // level so a newly added level stays locked until A1 (or earlier) is
        // finished.
        guard let course = level.course else { return nil }
        let sortedLevels = course.levels.sorted { $0.orderIndex < $1.orderIndex }
        guard let levelIndex = sortedLevels.firstIndex(where: { $0.id == level.id }),
              levelIndex > 0 else { return nil }
        let previousLevelUnits = sortedLevels[levelIndex - 1].units.sorted { $0.orderIndex < $1.orderIndex }
        guard let lastUnitOfPreviousLevel = previousLevelUnits.last else { return nil }
        return lastUnitOfPreviousLevel.lessons.sorted { $0.orderIndex < $1.orderIndex }.last
    }

    /// Star count derived from best accuracy. Matches `LessonResultsView`.
    static func stars(forAccuracy accuracy: Double) -> Int {
        if accuracy >= 0.9 { return 3 }
        if accuracy >= 0.6 { return 2 }
        return 1
    }

    // MARK: - Recording completion

    /// Records a finished lesson run: updates/creates `LessonProgress` for the
    /// user+lesson pair and `ExerciseProgress` for every exercise.
    /// `reviewDueAt` is intentionally left untouched (spaced repetition is a
    /// later phase). Idempotent per attempt: repeated calls increment
    /// `attempts` instead of creating duplicate records.
    @discardableResult
    func recordCompletion(
        user: UserProfile,
        lesson: Lesson,
        exercises: [Exercise],
        results: [ExerciseResult],
        accuracy: Double
    ) throws -> LessonProgress {
        let lessonProgress = try fetchOrCreateLessonProgress(user: user, lesson: lesson)
        lessonProgress.status = .completed
        lessonProgress.attempts += 1
        lessonProgress.bestAccuracy = max(lessonProgress.bestAccuracy, accuracy)
        lessonProgress.lastCompletedAt = Date()

        for (exercise, result) in zip(exercises, results) {
            guard result != .skipped else { continue }
            let exerciseProgress = try fetchOrCreateExerciseProgress(user: user, exercise: exercise)
            switch result {
            case .correct:
                exerciseProgress.correctCount += 1
            case .incorrect:
                exerciseProgress.incorrectCount += 1
            case .skipped:
                break
            }
            exerciseProgress.lastResult = result == .correct
            exerciseProgress.lastAnsweredAt = Date()
        }

        try context.save()
        return lessonProgress
    }

    private func fetchOrCreateLessonProgress(user: UserProfile, lesson: Lesson) throws -> LessonProgress {
        let lessonID = lesson.id
        let predicate = #Predicate<LessonProgress> { $0.lesson?.id == lessonID }
        let existing = try context.fetch(FetchDescriptor<LessonProgress>(predicate: predicate))
            .first { $0.user?.id == user.id }

        if let existing { return existing }

        let progress = LessonProgress(status: .completed, user: user, lesson: lesson)
        context.insert(progress)
        return progress
    }

    private func fetchOrCreateExerciseProgress(user: UserProfile, exercise: Exercise) throws -> ExerciseProgress {
        let exerciseID = exercise.id
        let predicate = #Predicate<ExerciseProgress> { $0.exercise?.id == exerciseID }
        let existing = try context.fetch(FetchDescriptor<ExerciseProgress>(predicate: predicate))
            .first { $0.user?.id == user.id }

        if let existing { return existing }

        let progress = ExerciseProgress(user: user, exercise: exercise)
        context.insert(progress)
        return progress
    }
}
