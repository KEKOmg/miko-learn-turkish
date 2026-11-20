import Foundation
import Observation

/// Drives the Profile screen: loads the user's stats and achievements into
/// an immutable `ProfileSnapshot`. All SwiftData access goes through the
/// repositories; the view never touches the context.
@MainActor
@Observable
final class ProfileViewModel {

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var snapshot: ProfileSnapshot?

    private let lessonProgressRepository: LessonProgressRepository
    private let achievementRepository: AchievementRepository
    private let heartsRepository: HeartsRepository?

    init(
        lessonProgressRepository: LessonProgressRepository,
        achievementRepository: AchievementRepository,
        heartsRepository: HeartsRepository?
    ) {
        self.lessonProgressRepository = lessonProgressRepository
        self.achievementRepository = achievementRepository
        self.heartsRepository = heartsRepository
    }

    /// Loads the profile snapshot. Safe to call repeatedly.
    func load() {
        phase = .loading
        do {
            guard let user = try? lessonProgressRepository.fetchPrimaryUserProfile() else {
                phase = .failed(String(localized: "profile.error.loadFailed"))
                return
            }
            let stats = try lessonProgressRepository.fetchUserStats()
            let catalog = try achievementRepository.fetchCatalog()
            let earned = try achievementRepository.fetchEarnedAchievements(for: user)
            let earnedByKey: [String: UserAchievement] = Dictionary(
                earned.compactMap { ua in
                    guard let key = ua.achievement?.key else { return nil }
                    return (key, ua)
                },
                uniquingKeysWith: { first, _ in first }
            )

            // Regenerate hearts before reading so the profile shows the
            // current count.
            if let heartsRepository {
                _ = try? heartsRepository.regenerateIfNeeded(for: user)
            }
            let hearts = try? heartsRepository?.fetchHearts(for: user)

            let perfectCount = try achievementRepository.fetchPerfectLessonCount(for: user)
            let state = AchievementEngine.State(
                xp: user.progress?.xp ?? 0,
                currentStreak: user.progress?.streak?.currentStreak ?? 0,
                totalLessonsCompleted: user.progress?.totalLessonsCompleted ?? 0,
                perfectLessonCount: perfectCount
            )

            let rows: [ProfileSnapshot.AchievementRow] = catalog.map { achievement in
                let entry = AchievementCatalog.entries.first { $0.key == achievement.key }
                let kind: ProfileSnapshot.AchievementRow.Kind
                if let earnedRow = earnedByKey[achievement.key] {
                    kind = .earned(date: earnedRow.earnedAt)
                } else {
                    let progress: Double
                    if let entry {
                        progress = AchievementEngine.progress(entry, state: state)
                    } else {
                        progress = 0
                    }
                    kind = .locked(progress: progress)
                }
                return ProfileSnapshot.AchievementRow(
                    id: achievement.id.uuidString,
                    key: achievement.key,
                    titleKey: achievement.titleKey,
                    descriptionKey: achievement.descriptionKey,
                    icon: achievement.icon,
                    kind: kind
                )
            }

            let stat = ProfileSnapshot.Stat(
                xp: stats?.xp ?? 0,
                streakDays: stats?.streakDays ?? 0,
                heartsRemaining: hearts?.currentHearts ?? stats?.heartsRemaining ?? 0,
                heartsTotal: hearts?.maxHearts ?? stats?.heartsTotal ?? 0,
                lessonsCompleted: user.progress?.totalLessonsCompleted ?? 0
            )

            snapshot = ProfileSnapshot(stat: stat, achievements: rows)
            phase = .ready
        } catch {
            phase = .failed(String(localized: "profile.error.loadFailed"))
        }
    }
}
