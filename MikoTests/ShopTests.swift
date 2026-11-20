import Foundation
import SwiftData
import Testing
@testable import Miko

/// Tests for the Shop heart-refill economy: `GamificationRepository.spendGems`,
/// `HeartsRepository.refillHearts`, and the `ShopViewModel` orchestration that
/// ties them together. Covers success, insufficient-gems, already-full, and
/// repeated-purchase scenarios, plus the invariants (gems ≥ 0, hearts ≤ max).
@MainActor
struct ShopTests {

    // MARK: - Fixtures

    private struct Fixture {
        let context: ModelContext
        let user: UserProfile
        let lessonProgressRepository: LessonProgressRepository
        let heartsRepository: HeartsRepository
        let gamificationRepository: GamificationRepository
    }

    /// Builds a fixture with a user, progress (with `gems`), and hearts
    /// (`currentHearts` / `maxHearts`).
    private func makeFixture(
        gems: Int = 0,
        currentHearts: Int = 5,
        maxHearts: Int = 5
    ) throws -> Fixture {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)

        let progress = UserProgress()
        progress.gems = gems
        progress.user = user
        context.insert(progress)

        let hearts = Hearts(
            currentHearts: currentHearts,
            maxHearts: maxHearts,
            user: user
        )
        context.insert(hearts)

        try context.save()

        return Fixture(
            context: context,
            user: user,
            lessonProgressRepository: LessonProgressRepository(context: context),
            heartsRepository: HeartsRepository(context: context),
            gamificationRepository: GamificationRepository(context: context)
        )
    }

    private func makeViewModel(_ fixture: Fixture) -> ShopViewModel {
        ShopViewModel(
            lessonProgressRepository: fixture.lessonProgressRepository,
            heartsRepository: fixture.heartsRepository,
            gamificationRepository: fixture.gamificationRepository
        )
    }

    @Test func reloadReflectsHeartsSpentOutsideShop() throws {
        let f = try makeFixture(gems: 30, currentHearts: 5, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        #expect(vm.snapshot?.heartsRemaining == 5)

        _ = try f.heartsRepository.decrementHeart(for: f.user)
        _ = try f.heartsRepository.decrementHeart(for: f.user)
        vm.load()

        #expect(vm.snapshot?.heartsRemaining == 3)
        #expect(vm.snapshot?.heartsTotal == 5)
    }

    // MARK: - GamificationRepository.spendGems

    @Test func spendGemsSucceedsWhenSufficient() throws {
        let f = try makeFixture(gems: 50)
        let result = try f.gamificationRepository.spendGems(20, for: f.user)
        #expect(result == true)
        #expect(f.user.progress?.gems == 30)
    }

    @Test func spendGemsFailsWhenInsufficient() throws {
        let f = try makeFixture(gems: 10)
        let result = try f.gamificationRepository.spendGems(20, for: f.user)
        #expect(result == false)
        #expect(f.user.progress?.gems == 10)
    }

    @Test func spendGemsFailsAtExactZero() throws {
        let f = try makeFixture(gems: 0)
        let result = try f.gamificationRepository.spendGems(20, for: f.user)
        #expect(result == false)
        #expect(f.user.progress?.gems == 0)
    }

    @Test func spendGemsNeverMakesGemsNegative() throws {
        let f = try makeFixture(gems: 5)
        _ = try f.gamificationRepository.spendGems(20, for: f.user)
        #expect(f.user.progress?.gems == 5)
    }

    // MARK: - Atomic heart-refill purchase

    @Test func purchaseHeartRefillMutatesBothBalances() throws {
        let f = try makeFixture(gems: 30, currentHearts: 2, maxHearts: 5)

        let purchased = try f.gamificationRepository.purchaseHeartRefill(
            cost: 20,
            for: f.user
        )

        #expect(purchased == true)
        #expect(f.user.progress?.gems == 10)
        #expect(try f.heartsRepository.fetchHearts(for: f.user)?.currentHearts == 5)
    }

    @Test func purchaseHeartRefillIsNoOpWhenInvalid() throws {
        let f = try makeFixture(gems: 10, currentHearts: 2, maxHearts: 5)

        let purchased = try f.gamificationRepository.purchaseHeartRefill(
            cost: 20,
            for: f.user
        )

        #expect(purchased == false)
        #expect(f.user.progress?.gems == 10)
        #expect(try f.heartsRepository.fetchHearts(for: f.user)?.currentHearts == 2)
    }

    // MARK: - HeartsRepository.refillHearts

    @Test func refillHeartsRestoresToMax() throws {
        let f = try makeFixture(currentHearts: 2, maxHearts: 5)
        let hearts = try f.heartsRepository.refillHearts(for: f.user)
        #expect(hearts?.currentHearts == 5)
        #expect(hearts?.maxHearts == 5)
    }

    @Test func refillHeartsAtMaxStaysAtMax() throws {
        let f = try makeFixture(currentHearts: 5, maxHearts: 5)
        let hearts = try f.heartsRepository.refillHearts(for: f.user)
        #expect(hearts?.currentHearts == 5)
    }

    @Test func refillHeartsNeverExceedsMax() throws {
        let f = try makeFixture(currentHearts: 3, maxHearts: 5)
        _ = try f.heartsRepository.refillHearts(for: f.user)
        let refetched = try f.heartsRepository.fetchHearts(for: f.user)
        #expect(refetched?.currentHearts == 5)
        #expect(refetched?.currentHearts ?? 0 <= refetched?.maxHearts ?? 0)
    }

    @Test func refillHeartsReturnsNilWhenNoRow() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        try context.save()
        let repo = HeartsRepository(context: context)

        #expect(try repo.refillHearts(for: user) == nil)
    }

    // MARK: - ShopViewModel: success

    @Test func refillSucceedsWhenGemsSufficient() throws {
        let f = try makeFixture(gems: 30, currentHearts: 2, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        #expect(vm.snapshot?.gems == 30)
        #expect(vm.snapshot?.heartsRemaining == 2)

        vm.refillHearts()

        #expect(vm.lastRefillSucceeded == true)
        #expect(vm.snapshot?.heartsRemaining == 5)
        #expect(vm.snapshot?.gems == 10)
    }

    @Test func refillDeductsExactlyRefillCost() throws {
        let f = try makeFixture(gems: 25, currentHearts: 1, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        vm.refillHearts()

        #expect(vm.snapshot?.gems == 25 - ShopViewModel.refillCost)
        #expect(f.user.progress?.gems == 25 - ShopViewModel.refillCost)
    }

    @Test func refillRestoresHeartsToMax() throws {
        let f = try makeFixture(gems: 100, currentHearts: 0, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        vm.refillHearts()

        #expect(vm.snapshot?.heartsRemaining == 5)
        #expect(vm.snapshot?.heartsRemaining == vm.snapshot?.heartsTotal)
    }

    // MARK: - ShopViewModel: failure / no-op

    @Test func refillFailsWhenGemsInsufficient() throws {
        let f = try makeFixture(gems: 10, currentHearts: 2, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        vm.refillHearts()

        #expect(vm.lastRefillSucceeded == false)
        #expect(vm.snapshot?.gems == 10)
        #expect(vm.snapshot?.heartsRemaining == 2)
    }

    @Test func failedRefillDoesNotChangeGems() throws {
        let f = try makeFixture(gems: 10, currentHearts: 2, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        let gemsBefore = vm.snapshot?.gems
        vm.refillHearts()
        #expect(vm.snapshot?.gems == gemsBefore)
        #expect(f.user.progress?.gems == 10)
    }

    @Test func failedRefillDoesNotChangeHearts() throws {
        let f = try makeFixture(gems: 10, currentHearts: 2, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        let heartsBefore = vm.snapshot?.heartsRemaining
        vm.refillHearts()
        #expect(vm.snapshot?.heartsRemaining == heartsBefore)
        #expect(try f.heartsRepository.fetchHearts(for: f.user)?.currentHearts == 2)
    }

    @Test func refillUnavailableWhenHeartsFull() throws {
        let f = try makeFixture(gems: 100, currentHearts: 5, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        #expect(vm.snapshot?.isHeartsFull == true)
        #expect(vm.snapshot?.canRefill == false)

        vm.refillHearts()

        #expect(vm.lastRefillSucceeded == false)
        #expect(vm.snapshot?.gems == 100)
        #expect(vm.snapshot?.heartsRemaining == 5)
    }

    // MARK: - ShopViewModel: repeated purchases

    @Test func repeatedRefillsWorkWhenEnoughGems() throws {
        let f = try makeFixture(gems: 60, currentHearts: 3, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()

        // First refill: 60 - 20 = 40 gems, hearts → 5.
        vm.refillHearts()
        #expect(vm.snapshot?.gems == 40)
        #expect(vm.snapshot?.heartsRemaining == 5)

        // Simulate losing 2 hearts.
        _ = try f.heartsRepository.decrementHeart(for: f.user)
        _ = try f.heartsRepository.decrementHeart(for: f.user)
        vm.load()
        #expect(vm.snapshot?.heartsRemaining == 3)

        // Second refill: 40 - 20 = 20 gems, hearts → 5.
        vm.refillHearts()
        #expect(vm.snapshot?.gems == 20)
        #expect(vm.snapshot?.heartsRemaining == 5)

        // Simulate losing 1 heart.
        _ = try f.heartsRepository.decrementHeart(for: f.user)
        vm.load()
        #expect(vm.snapshot?.heartsRemaining == 4)

        // Third refill: 20 - 20 = 0 gems, hearts → 5.
        vm.refillHearts()
        #expect(vm.snapshot?.gems == 0)
        #expect(vm.snapshot?.heartsRemaining == 5)
    }

    @Test func repeatedRefillStopsWhenGemsRunOut() throws {
        let f = try makeFixture(gems: 25, currentHearts: 2, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()

        // First refill succeeds: 25 - 20 = 5 gems.
        vm.refillHearts()
        #expect(vm.lastRefillSucceeded == true)
        #expect(vm.snapshot?.gems == 5)

        // Lose a heart.
        _ = try f.heartsRepository.decrementHeart(for: f.user)
        vm.load()
        #expect(vm.snapshot?.heartsRemaining == 4)

        // Second refill fails: only 5 gems left.
        vm.refillHearts()
        #expect(vm.lastRefillSucceeded == false)
        #expect(vm.snapshot?.gems == 5)
        #expect(vm.snapshot?.heartsRemaining == 4)
    }

    // MARK: - Invariants

    @Test func gemsNeverBecomeNegative() throws {
        let f = try makeFixture(gems: 0, currentHearts: 0, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        vm.refillHearts()
        #expect(f.user.progress?.gems == 0)
        #expect((f.user.progress?.gems ?? 0) >= 0)
    }

    @Test func heartsNeverExceedMaxHearts() throws {
        let f = try makeFixture(gems: 100, currentHearts: 4, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        vm.refillHearts()
        #expect(vm.snapshot?.heartsRemaining ?? 0 <= vm.snapshot?.heartsTotal ?? 0)
    }

    // MARK: - Persistence

    @Test func refillPersistsAfterRefetch() throws {
        let f = try makeFixture(gems: 30, currentHearts: 1, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        vm.refillHearts()

        // Refetch directly from the store — not from the ViewModel snapshot.
        let refetchedHearts = try f.heartsRepository.fetchHearts(for: f.user)
        #expect(refetchedHearts?.currentHearts == 5)
        #expect(f.user.progress?.gems == 10)

        // A fresh ViewModel sees the persisted state.
        let vm2 = makeViewModel(f)
        vm2.load()
        #expect(vm2.snapshot?.heartsRemaining == 5)
        #expect(vm2.snapshot?.gems == 10)
    }

    // MARK: - Snapshot computed properties

    @Test func snapshotCanRefillIsFalseWhenFull() throws {
        let f = try makeFixture(gems: 100, currentHearts: 5, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        #expect(vm.snapshot?.canRefill == false)
    }

    @Test func snapshotCanRefillIsFalseWhenBroke() throws {
        let f = try makeFixture(gems: 5, currentHearts: 2, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        #expect(vm.snapshot?.canRefill == false)
    }

    @Test func snapshotCanRefillIsTrueWhenGemsAndRoomAvailable() throws {
        let f = try makeFixture(gems: 20, currentHearts: 3, maxHearts: 5)
        let vm = makeViewModel(f)
        vm.load()
        #expect(vm.snapshot?.canRefill == true)
    }

    @Test func refillCostIsTwenty() {
        #expect(ShopViewModel.refillCost == 20)
    }
}
