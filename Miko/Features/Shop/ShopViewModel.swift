import Foundation
import Observation

/// Drives the Shop screen: loads the user's gems and hearts into an immutable
/// snapshot and performs the "refill hearts" purchase. All SwiftData access
/// goes through `GamificationRepository` and `HeartsRepository`; the view
/// never touches the context.
@MainActor
@Observable
final class ShopViewModel {

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// Immutable shop state consumed by the view.
    struct Snapshot: Equatable {
        let gems: Int
        let heartsTotal: Int
        let heartsRemaining: Int
        let refillCost: Int

        /// Hearts are already at max — refilling is unavailable.
        var isHeartsFull: Bool {
            heartsRemaining >= heartsTotal
        }

        /// User has enough gems to afford a refill.
        var canAffordRefill: Bool {
            gems >= refillCost
        }

        /// The refill button should be enabled.
        var canRefill: Bool {
            !isHeartsFull && canAffordRefill
        }
    }

    /// Single source of truth for the refill price (in gems).
    static let refillCost = 20

    private(set) var phase: Phase = .loading
    private(set) var snapshot: Snapshot?

    /// Set briefly after a successful refill so the view can show feedback.
    private(set) var lastRefillSucceeded: Bool = false

    private let lessonProgressRepository: LessonProgressRepository
    private let heartsRepository: HeartsRepository?
    private let gamificationRepository: GamificationRepository?

    init(
        lessonProgressRepository: LessonProgressRepository,
        heartsRepository: HeartsRepository?,
        gamificationRepository: GamificationRepository?
    ) {
        self.lessonProgressRepository = lessonProgressRepository
        self.heartsRepository = heartsRepository
        self.gamificationRepository = gamificationRepository
    }

    // MARK: - Loading

    /// Loads the shop snapshot. Safe to call repeatedly.
    func load() {
        phase = .loading
        lastRefillSucceeded = false
        do {
            guard let user = try lessonProgressRepository.fetchPrimaryUserProfile() else {
                phase = .failed(String(localized: "shop.error.loadFailed"))
                return
            }
            let gems = user.progress?.gems ?? 0

            // Regenerate hearts before reading so the snapshot is current.
            if let heartsRepository {
                _ = try? heartsRepository.regenerateIfNeeded(for: user)
            }
            let hearts = try? heartsRepository?.fetchHearts(for: user)
            let heartsTotal = hearts?.maxHearts ?? HeartsRepository.defaultMaxHearts
            let heartsRemaining = hearts?.currentHearts ?? HeartsRepository.defaultMaxHearts

            snapshot = Snapshot(
                gems: gems,
                heartsTotal: heartsTotal,
                heartsRemaining: heartsRemaining,
                refillCost: Self.refillCost
            )
            phase = .ready
        } catch {
            phase = .failed(String(localized: "shop.error.loadFailed"))
        }
    }

    // MARK: - Purchase

    /// Attempts to refill hearts to max for the refill cost in gems.
    /// Does nothing when hearts are already full or gems are insufficient.
    /// On success, deducts gems, restores hearts, reloads the snapshot, and
    /// triggers a success haptic.
    func refillHearts() {
        guard let gamificationRepository,
              heartsRepository != nil,
              let user = try? lessonProgressRepository.fetchPrimaryUserProfile()
        else { return }

        do {
            // Re-read and mutate both balances inside one repository
            // transaction. The snapshot may be stale after switching tabs.
            let purchased = try gamificationRepository.purchaseHeartRefill(
                cost: Self.refillCost,
                for: user
            )
            guard purchased else { return }
            Haptics.achievementEarned(enabled: user.settings?.hapticsEnabled ?? true)
            load()
            lastRefillSucceeded = true
        } catch {
            lastRefillSucceeded = false
        }
    }
}
