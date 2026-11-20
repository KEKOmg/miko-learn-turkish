import Foundation
import SwiftData
import Testing
@testable import Miko

/// Tests for `HeartsRepository`: fetch, decrement, play eligibility,
/// and lazy regeneration (including the 30-minute interval, multi-interval
/// elapsed time, max cap, and remaining-time calculation).
@MainActor
struct HeartsRepositoryTests {

    private static let interval = HeartsRepository.regenerationInterval // 30 * 60

    private func makeFixture(initialHearts: Int = 5, lastRegeneratedAt: Date = .now) throws -> (
        ModelContext, UserProfile, HeartsRepository
    ) {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)

        let hearts = Hearts(
            currentHearts: initialHearts,
            maxHearts: HeartsRepository.defaultMaxHearts,
            lastRegeneratedAt: lastRegeneratedAt,
            user: user
        )
        context.insert(hearts)
        try context.save()

        return (context, user, HeartsRepository(context: context))
    }

    // MARK: - Fetch / defaults

    @Test func fetchReturnsHeartsForUser() throws {
        let (_, user, repo) = try makeFixture()
        let hearts = try repo.fetchHearts(for: user)
        #expect(hearts != nil)
        #expect(hearts?.currentHearts == 5)
        #expect(hearts?.maxHearts == 5)
    }

    @Test func fetchReturnsNilWhenNoHeartsRow() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        try context.save()
        let repo = HeartsRepository(context: context)

        #expect(try repo.fetchHearts(for: user) == nil)
    }

    // MARK: - Can play

    @Test func canPlayTrueWhenHeartsAvailable() throws {
        let (_, user, repo) = try makeFixture(initialHearts: 1)
        #expect(try repo.canPlay(for: user) == true)
    }

    @Test func canPlayFalseAtZero() throws {
        let (_, user, repo) = try makeFixture(initialHearts: 0)
        #expect(try repo.canPlay(for: user) == false)
    }

    // MARK: - Decrement

    @Test func decrementReducesByOne() throws {
        let (_, user, repo) = try makeFixture(initialHearts: 5)
        let result = try repo.decrementHeart(for: user)
        #expect(result == 4)
        #expect(try repo.fetchHearts(for: user)?.currentHearts == 4)
    }

    @Test func decrementNeverGoesBelowZero() throws {
        let (_, user, repo) = try makeFixture(initialHearts: 0)
        let result = try repo.decrementHeart(for: user)
        #expect(result == 0)
        #expect(try repo.fetchHearts(for: user)?.currentHearts == 0)
    }

    @Test func decrementMultipleTimesStopsAtZero() throws {
        let (_, user, repo) = try makeFixture(initialHearts: 2)
        _ = try repo.decrementHeart(for: user)
        _ = try repo.decrementHeart(for: user)
        _ = try repo.decrementHeart(for: user)
        _ = try repo.decrementHeart(for: user)
        #expect(try repo.fetchHearts(for: user)?.currentHearts == 0)
    }

    @Test func unlimitedTestingModeKeepsHeartsFull() throws {
        let (context, user, _) = try makeFixture(initialHearts: 0)
        let repo = HeartsRepository(context: context, unlimitedHearts: true)

        let regenerated = try repo.regenerateIfNeeded(for: user)
        #expect(regenerated?.currentHearts == HeartsRepository.defaultMaxHearts)
        #expect(try repo.canPlay(for: user))
        #expect(try repo.decrementHeart(for: user) == HeartsRepository.defaultMaxHearts)
        #expect(try repo.secondsUntilNextHeart(for: user) == 0)
    }

    // MARK: - Regeneration

    @Test func regenerateNoOpBeforeInterval() throws {
        let base = Date(timeIntervalSince1970: 0)
        let (_, user, repo) = try makeFixture(initialHearts: 2, lastRegeneratedAt: base)
        let now = base.addingTimeInterval(Self.interval - 60) // 29m
        let hearts = try repo.regenerateIfNeeded(for: user, now: now)
        #expect(hearts?.currentHearts == 2)
        #expect(hearts?.lastRegeneratedAt == base)
    }

    @Test func regenerateAddsOneAfterExactlyInterval() throws {
        let base = Date(timeIntervalSince1970: 0)
        let (_, user, repo) = try makeFixture(initialHearts: 2, lastRegeneratedAt: base)
        let now = base.addingTimeInterval(Self.interval) // 30m
        let hearts = try repo.regenerateIfNeeded(for: user, now: now)
        #expect(hearts?.currentHearts == 3)
        #expect(hearts?.lastRegeneratedAt == base.addingTimeInterval(Self.interval))
    }

    @Test func regenerateAddsMultipleAfterSeveralIntervals() throws {
        let base = Date(timeIntervalSince1970: 0)
        let (_, user, repo) = try makeFixture(initialHearts: 1, lastRegeneratedAt: base)
        let now = base.addingTimeInterval(Self.interval * 2 + 60) // 60m + 1m
        let hearts = try repo.regenerateIfNeeded(for: user, now: now)
        #expect(hearts?.currentHearts == 3)
        // Clock advanced by the two whole intervals; the leftover 60s counts
        // toward the next heart.
        #expect(hearts?.lastRegeneratedAt == base.addingTimeInterval(Self.interval * 2))
    }

    @Test func regenerateCapsAtMax() throws {
        let base = Date(timeIntervalSince1970: 0)
        let (_, user, repo) = try makeFixture(initialHearts: 3, lastRegeneratedAt: base)
        let now = base.addingTimeInterval(Self.interval * 10) // 300m
        let hearts = try repo.regenerateIfNeeded(for: user, now: now)
        #expect(hearts?.currentHearts == 5)
        #expect(hearts?.maxHearts == 5)
    }

    @Test func regenerateAtMaxRefreshesClock() throws {
        let base = Date(timeIntervalSince1970: 0)
        let (_, user, repo) = try makeFixture(initialHearts: 5, lastRegeneratedAt: base)
        let now = base.addingTimeInterval(3600)
        let hearts = try repo.regenerateIfNeeded(for: user, now: now)
        #expect(hearts?.currentHearts == 5)
        #expect(hearts?.lastRegeneratedAt == now)
    }

    @Test func regenerateNoOpWhenNoHeartsRow() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        try context.save()
        let repo = HeartsRepository(context: context)

        #expect(try repo.regenerateIfNeeded(for: user) == nil)
    }

    // MARK: - Remaining time

    @Test func secondsUntilNextHeartAtMaxReturnsZero() throws {
        let (_, user, repo) = try makeFixture(initialHearts: 5)
        #expect(try repo.secondsUntilNextHeart(for: user) == 0)
    }

    @Test func secondsUntilNextHeartReturnsRemaining() throws {
        let base = Date(timeIntervalSince1970: 0)
        let (_, user, repo) = try makeFixture(initialHearts: 0, lastRegeneratedAt: base)
        let now = base.addingTimeInterval(10 * 60) // 10m elapsed → 20m remaining
        let remaining = try repo.secondsUntilNextHeart(for: user, now: now)
        #expect(abs(remaining - (Self.interval - 600)) < 0.001)
    }

    @Test func secondsUntilNextHeartAfterPartialRegen() throws {
        let base = Date(timeIntervalSince1970: 0)
        let (_, user, repo) = try makeFixture(initialHearts: 0, lastRegeneratedAt: base)
        // 30m + 5m elapsed → one heart regenerated at 30m; 25m remain to next.
        let now = base.addingTimeInterval(Self.interval + 300)
        _ = try repo.regenerateIfNeeded(for: user, now: now)
        let remaining = try repo.secondsUntilNextHeart(for: user, now: now)
        #expect(abs(remaining - (Self.interval - 300)) < 0.001)
    }
}
