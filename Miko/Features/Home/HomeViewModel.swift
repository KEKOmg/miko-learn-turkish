import Foundation
import Observation
import SwiftData

/// Drives the Home screen: loads user stats and the next unfinished lesson,
/// exposing immutable snapshots to the view. All SwiftData access goes
/// through `LessonProgressRepository`; the view never touches the context.
@MainActor
@Observable
final class HomeViewModel {

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var stats: UserStatsSnapshot?
    private(set) var nextLesson: NextLessonSnapshot?
    private(set) var secondsUntilNextHeart: TimeInterval = 0
    private(set) var isDailyRewardClaimed = false

    static let dailyRewardGems = 25

    private let repository: LessonProgressRepository
    private let heartsRepository: HeartsRepository?
    private let gamificationRepository: GamificationRepository?
    private let courseKey: String
    private let defaults: UserDefaults

    init(
        repository: LessonProgressRepository,
        heartsRepository: HeartsRepository? = nil,
        gamificationRepository: GamificationRepository? = nil,
        courseKey: String = "course.ru-tr",
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.heartsRepository = heartsRepository
        self.gamificationRepository = gamificationRepository
        self.courseKey = courseKey
        self.defaults = defaults
    }

    /// Loads stats and the next lesson. Safe to call repeatedly; later calls
    /// refresh the data (used after returning from a completed lesson).
    func load() {
        phase = .loading
        do {
            // Reset the daily goal on a new day before reading stats so the
            // Home screen reflects today's progress, not yesterday's.
            if let gamificationRepository,
               let user = try? repository.fetchPrimaryUserProfile() {
                _ = try? gamificationRepository.resetDailyGoalIfNeeded(for: user)
            }
            if let heartsRepository,
               let user = try? repository.fetchPrimaryUserProfile() {
                _ = try? heartsRepository.regenerateIfNeeded(for: user)
            }
            stats = try repository.fetchUserStats()
            if let heartsRepository,
               let user = try? repository.fetchPrimaryUserProfile() {
                secondsUntilNextHeart =
                    (try? heartsRepository.secondsUntilNextHeart(for: user)) ?? 0
            } else {
                secondsUntilNextHeart = 0
            }
            refreshDailyRewardState()
            if let lesson = try repository.fetchNextUnfinishedLesson(courseKey: courseKey) {
                let unitTitle = lesson.unit?.titleKey ?? ""
                nextLesson = NextLessonSnapshot(
                    id: lesson.id,
                    titleKey: lesson.titleKey,
                    unitTitleKey: unitTitle
                )
            } else {
                nextLesson = nil
            }
            phase = .ready
        } catch {
            phase = .failed(String(localized: "home.error.loadFailed"))
        }
    }

    /// True when the user has at least one heart and can start a lesson.
    var canStartLesson: Bool {
        (stats?.heartsRemaining ?? 0) > 0
    }

    var canClaimDailyReward: Bool {
        stats?.isDailyGoalReached == true && !isDailyRewardClaimed
    }

    var xpUntilDailyReward: Int {
        guard let stats else { return 0 }
        return max(0, stats.dailyGoalXP - stats.dailyGoalEarned)
    }

    func claimDailyReward() {
        guard canClaimDailyReward,
              let gamificationRepository,
              let user = try? repository.fetchPrimaryUserProfile() else { return }
        do {
            _ = try gamificationRepository.addGems(Self.dailyRewardGems, for: user)
            defaults.set(Date(), forKey: rewardClaimKey(for: user))
            isDailyRewardClaimed = true
            Haptics.achievementEarned(enabled: user.settings?.hapticsEnabled ?? true)
        } catch {
            return
        }
    }

    private func refreshDailyRewardState() {
        guard let user = try? repository.fetchPrimaryUserProfile(),
              let claimedAt = defaults.object(forKey: rewardClaimKey(for: user)) as? Date else {
            isDailyRewardClaimed = false
            return
        }
        isDailyRewardClaimed = Calendar.current.isDateInToday(claimedAt)
    }

    private func rewardClaimKey(for user: UserProfile) -> String {
        "dailyReward.claimedAt.\(user.id.uuidString)"
    }
}
