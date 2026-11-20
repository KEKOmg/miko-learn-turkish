import Foundation
import SwiftData

/// Owns the heart economy persistence: fetching, decrementing, regenerating,
/// and querying play eligibility. Regeneration is computed lazily from
/// `lastRegeneratedAt` — no background timer required.
///
/// All mutations go through this repository so neither the ViewModel nor
/// SwiftUI views perform raw SwiftData writes.
struct HeartsRepository {
    static let defaultMaxHearts = 5
    static let regenerationInterval: TimeInterval = 30 * 60

    private let context: ModelContext
    private let unlimitedHearts: Bool

    init(context: ModelContext, unlimitedHearts: Bool = false) {
        self.context = context
        self.unlimitedHearts = unlimitedHearts
    }

    // MARK: - Fetching

    /// Returns the `Hearts` row for the given user, or `nil` when none exists
    /// (e.g. before bootstrap). Never throws for malformed data.
    func fetchHearts(for user: UserProfile) throws -> Hearts? {
        let userID = user.id
        let predicate = #Predicate<Hearts> { $0.user?.id == userID }
        var descriptor = FetchDescriptor<Hearts>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Eligibility

    /// True when the user has at least one heart and can start a lesson.
    func canPlay(for user: UserProfile) throws -> Bool {
        if unlimitedHearts { return true }
        return try fetchHearts(for: user)?.currentHearts ?? 0 > 0
    }

    // MARK: - Decrement

    /// Decrements one heart for an incorrect answer. Never goes below 0.
    /// When no `Hearts` row exists yet (e.g. a pre-Phase-5 upgrade that was
    /// not caught by `UserBootstrap`), lazily creates one with the default
    /// max and applies the decrement so the user starts at `max - 1`.
    @discardableResult
    func decrementHeart(for user: UserProfile) throws -> Int {
        if unlimitedHearts {
            guard let hearts = try fetchHearts(for: user) else {
                return Self.defaultMaxHearts
            }
            if hearts.currentHearts != hearts.maxHearts {
                hearts.currentHearts = hearts.maxHearts
                hearts.lastRegeneratedAt = Date()
                try context.save()
            }
            return hearts.maxHearts
        }

        if let hearts = try fetchHearts(for: user) {
            if hearts.currentHearts > 0 {
                hearts.currentHearts -= 1
            }
            try context.save()
            return hearts.currentHearts
        }
        // No Hearts row — lazily create one with the default max, then apply
        // the decrement for this incorrect answer.
        let hearts = Hearts(
            currentHearts: max(0, Self.defaultMaxHearts - 1),
            maxHearts: Self.defaultMaxHearts,
            user: user
        )
        context.insert(hearts)
        try context.save()
        return hearts.currentHearts
    }

    // MARK: - Refill

    /// Refills hearts to `maxHearts`. Used by the Shop. No-op (returns `nil`)
    /// when no `Hearts` row exists. Resets `lastRegeneratedAt` to `now` so the
    /// regeneration clock starts fresh from a full state.
    @discardableResult
    func refillHearts(for user: UserProfile, now: Date = Date()) throws -> Hearts? {
        guard let hearts = try fetchHearts(for: user) else { return nil }
        hearts.currentHearts = hearts.maxHearts
        hearts.lastRegeneratedAt = now
        try context.save()
        return hearts
    }

    // MARK: - Regeneration

    /// Regenerates hearts based on elapsed time since `lastRegeneratedAt`.
    /// One heart per `regenerationInterval` (30 minutes), capped at
    /// `maxHearts`. Updates `lastRegeneratedAt` to the consumed boundary so
    /// partial intervals are preserved. No-op when hearts is already full or
    /// no row exists.
    ///
    /// `now` is injectable for testing; defaults to `Date()`.
    @discardableResult
    func regenerateIfNeeded(for user: UserProfile, now: Date = Date()) throws -> Hearts? {
        guard let hearts = try fetchHearts(for: user) else { return nil }
        if unlimitedHearts {
            if hearts.currentHearts != hearts.maxHearts {
                hearts.currentHearts = hearts.maxHearts
                hearts.lastRegeneratedAt = now
                try context.save()
            }
            return hearts
        }
        if hearts.currentHearts >= hearts.maxHearts {
            // Already full — keep the reference clock current so a later loss
            // starts a fresh regeneration window.
            if hearts.lastRegeneratedAt != now {
                hearts.lastRegeneratedAt = now
                try context.save()
            }
            return hearts
        }

        let interval = Self.regenerationInterval
        let elapsed = now.timeIntervalSince(hearts.lastRegeneratedAt)
        guard elapsed >= interval else { return hearts }

        let fullIntervals = Int(elapsed / interval)
        let regenerated = min(fullIntervals, hearts.maxHearts - hearts.currentHearts)
        if regenerated > 0 {
            hearts.currentHearts += regenerated
            // Advance the clock by the consumed whole intervals; the leftover
            // partial interval counts toward the next heart.
            hearts.lastRegeneratedAt = hearts.lastRegeneratedAt.addingTimeInterval(
                TimeInterval(fullIntervals) * interval
            )
        } else {
            // No room to regenerate (e.g. capped) — keep the clock honest.
            hearts.lastRegeneratedAt = hearts.lastRegeneratedAt.addingTimeInterval(
                TimeInterval(fullIntervals) * interval
            )
        }
        try context.save()
        return hearts
    }

    /// Seconds remaining until the next heart regenerates. Returns 0 when
    /// hearts is already at max (no regeneration pending) or no row exists.
    func secondsUntilNextHeart(for user: UserProfile, now: Date = Date()) throws -> TimeInterval {
        if unlimitedHearts { return 0 }
        guard let hearts = try fetchHearts(for: user) else { return 0 }
        if hearts.currentHearts >= hearts.maxHearts { return 0 }
        let elapsed = now.timeIntervalSince(hearts.lastRegeneratedAt)
        let interval = Self.regenerationInterval
        let remaining = interval - (elapsed.truncatingRemainder(dividingBy: interval))
        if remaining <= 0 { return 0 }
        return remaining
    }
}
