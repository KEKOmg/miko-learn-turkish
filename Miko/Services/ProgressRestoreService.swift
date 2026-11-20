import Foundation
import SwiftData

/// Restores the signed-in user's stats from their Supabase profile row.
///
/// All restored metrics are monotonic counters, so merging is a per-field
/// `max(local, cloud)`: a newer device never regresses because of a stale
/// cloud copy, and a fresh device adopts whatever the cloud holds. Anything
/// the merge raised above the cloud copy is meant to be pushed back by the
/// caller through the regular sync path.
enum ProgressRestoreService {

    // MARK: - Pure merging

    /// Merges a freshly downloaded cloud row into the locally known progress.
    /// `local` is `nil` when the device has no measurable progress yet.
    static func merge(local: CloudProgress?, cloud: CloudProgress) -> CloudProgress {
        guard let local else { return cloud }
        return CloudProgress(
            username: cloud.username.isEmpty ? local.username : cloud.username,
            xp: max(local.xp, cloud.xp),
            streakDays: max(local.streakDays, cloud.streakDays),
            lessonsCompleted: max(local.lessonsCompleted, cloud.lessonsCompleted)
        )
    }

    // MARK: - Store access

    @MainActor
    static func currentLocalProgress(
        context: ModelContext,
        profileID: UUID? = nil
    ) -> CloudProgress? {
        guard let user = try? GamificationRepository(
            context: context,
            profileID: profileID
        ).fetchPrimaryUserProfile(),
              let progress = user.progress else { return nil }
        return CloudProgress(
            username: user.username,
            xp: progress.xp,
            streakDays: progress.streak?.currentStreak ?? 0,
            lessonsCompleted: progress.totalLessonsCompleted
        )
    }

    /// Writes merged values into local storage. Only grows counters; streak
    /// dates stay untouched except that an adopted higher streak claims today
    /// as active so the next real session does not reset it.
    @MainActor
    @discardableResult
    static func apply(
        _ progress: CloudProgress,
        context: ModelContext,
        profileID: UUID? = nil
    ) throws -> Bool {
        guard let user = try GamificationRepository(
            context: context,
            profileID: profileID
        ).fetchPrimaryUserProfile() else {
            return false
        }
        var didChange = false

        if user.username.isEmpty, !progress.username.isEmpty {
            user.username = progress.username
            didChange = true
        }

        if let storeProgress = user.progress {
            if progress.xp > storeProgress.xp {
                storeProgress.xp = progress.xp
                didChange = true
            }
            if progress.lessonsCompleted > storeProgress.totalLessonsCompleted {
                storeProgress.totalLessonsCompleted = progress.lessonsCompleted
                didChange = true
            }
            if let streak = storeProgress.streak,
               progress.streakDays > streak.currentStreak {
                streak.currentStreak = progress.streakDays
                streak.longestStreak = max(streak.longestStreak, progress.streakDays)
                streak.lastActiveDate = Calendar.current.startOfDay(for: Date())
                didChange = true
            }
        }

        try context.save()
        return didChange
    }

    @MainActor
    static func currentLocalLessonProgress(
        context: ModelContext,
        profileID: UUID
    ) throws -> [CloudLessonProgress] {
        let repository = LessonProgressRepository(context: context, profileID: profileID)
        guard let user = try repository.fetchPrimaryUserProfile() else { return [] }
        return try repository.fetchCompletedLessonProgress(user: user)
    }

    /// Restores completed lesson identities without invoking XP, streak,
    /// gems, daily-goal, achievement, or weekly-league reward paths.
    @MainActor
    @discardableResult
    static func hydrateLessonProgress(
        _ rows: [CloudLessonProgress],
        context: ModelContext,
        profileID: UUID
    ) throws -> Int {
        let repository = LessonProgressRepository(context: context, profileID: profileID)
        guard let user = try repository.fetchPrimaryUserProfile() else { return 0 }
        return try repository.hydrateCompletedLessons(rows, user: user)
    }
}
