import Foundation
import SwiftData
import Testing
@testable import Miko

/// Guards persistent-store recovery (CRITICAL-3).
///
/// The central invariant: a persistent-store failure must never be silently
/// converted into normal in-memory operation, and a damaged store must be
/// preserved rather than deleted.
@Suite(.serialized)
struct StoreRecoveryTests {

    // MARK: - StoreOutcome semantics

    @Test func persistentOutcomeNeedsNoUserNotice() {
        let outcome = ModelContainerFactory.StoreOutcome.persistent
        #expect(outcome.requiresUserNotice == false)
        #expect(outcome.isEphemeral == false)
    }

    @Test func recoveredFreshRequiresUserNoticeButStillPersists() {
        let outcome = ModelContainerFactory.StoreOutcome.recoveredFresh(preservedStoreURL: nil)
        #expect(outcome.requiresUserNotice == true)
        // Data written from now on is still saved to disk.
        #expect(outcome.isEphemeral == false)
    }

    @Test func inMemoryFallbackIsEphemeralAndRequiresNotice() {
        let outcome = ModelContainerFactory.StoreOutcome.inMemoryFallback
        #expect(outcome.requiresUserNotice == true)
        #expect(outcome.isEphemeral == true)
    }

    /// The three outcomes must remain distinguishable — collapsing them is
    /// exactly the silent-fallback bug this phase removes.
    @Test func outcomesAreDistinct() {
        let persistent = ModelContainerFactory.StoreOutcome.persistent
        let recovered = ModelContainerFactory.StoreOutcome.recoveredFresh(preservedStoreURL: nil)
        let inMemory = ModelContainerFactory.StoreOutcome.inMemoryFallback

        #expect(persistent != recovered)
        #expect(persistent != inMemory)
        #expect(recovered != inMemory)
    }

    @Test func recoveredFreshCarriesPreservedURL() {
        let url = URL(fileURLWithPath: "/tmp/default.store.corrupt-123")
        let outcome = ModelContainerFactory.StoreOutcome.recoveredFresh(preservedStoreURL: url)
        if case .recoveredFresh(let preserved) = outcome {
            #expect(preserved == url)
        } else {
            #expect(Bool(false), "Expected recoveredFresh")
        }
    }

    // MARK: - Store preservation (never delete)

    /// Builds an isolated directory with a fake store plus its sidecars.
    private func makeFakeStore(
        contents: String = "corrupt-store-bytes"
    ) throws -> (dir: URL, store: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "storerecovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = dir.appending(path: "default.store")
        try contents.write(to: store, atomically: true, encoding: .utf8)
        try "wal".write(to: URL(fileURLWithPath: store.path + "-wal"), atomically: true, encoding: .utf8)
        try "shm".write(to: URL(fileURLWithPath: store.path + "-shm"), atomically: true, encoding: .utf8)
        return (dir, store)
    }

    @Test func preserveRenamesStoreAndNeverDeletesIt() throws {
        let (dir, store) = try makeFakeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let preserved = try #require(ModelContainerFactory.preserveExistingStore(at: store))

        // Original path is free so a fresh store can be created there...
        #expect(FileManager.default.fileExists(atPath: store.path) == false)
        // ...but the data still exists under the preserved name.
        #expect(FileManager.default.fileExists(atPath: preserved.path))
        #expect(try String(contentsOf: preserved, encoding: .utf8) == "corrupt-store-bytes")
    }

    @Test func preservedStoreUsesCorruptTimestampSuffix() throws {
        let (dir, store) = try makeFakeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let preserved = try #require(ModelContainerFactory.preserveExistingStore(at: store))
        #expect(preserved.lastPathComponent.contains(".corrupt-"))
        #expect(preserved.lastPathComponent.hasPrefix("default.store."))
    }

    @Test func preserveMovesSidecarFilesAlongsideTheStore() throws {
        let (dir, store) = try makeFakeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let preserved = try #require(ModelContainerFactory.preserveExistingStore(at: store))

        #expect(FileManager.default.fileExists(atPath: preserved.path + "-wal"))
        #expect(FileManager.default.fileExists(atPath: preserved.path + "-shm"))
        #expect(FileManager.default.fileExists(atPath: store.path + "-wal") == false)
        #expect(FileManager.default.fileExists(atPath: store.path + "-shm") == false)
    }

    @Test func preserveReturnsNilWhenThereIsNoStore() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "does-not-exist-\(UUID().uuidString).store")
        #expect(ModelContainerFactory.preserveExistingStore(at: missing) == nil)
    }

    /// Two failures in a row must not overwrite the first preserved copy.
    @Test func repeatedPreservationKeepsDistinctCopies() throws {
        let (dir, store) = try makeFakeStore(contents: "first")
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = try #require(
            ModelContainerFactory.preserveExistingStore(
                at: store,
                now: Date(timeIntervalSince1970: 1_000_000)
            )
        )
        try "second".write(to: store, atomically: true, encoding: .utf8)
        let second = try #require(
            ModelContainerFactory.preserveExistingStore(
                at: store,
                now: Date(timeIntervalSince1970: 2_000_000)
            )
        )

        #expect(first != second)
        #expect(try String(contentsOf: first, encoding: .utf8) == "first")
        #expect(try String(contentsOf: second, encoding: .utf8) == "second")
    }

    // MARK: - AppState wiring

    @Test func appStateDefaultsToPersistentWithNoNotice() {
        let state = AppState()
        #expect(state.storeOutcome == .persistent)
        #expect(state.isShowingStorageNotice == false)
    }

    @Test func appStateShowsNoticeForRecoveredStore() {
        let state = AppState()
        state.storeOutcome = .recoveredFresh(preservedStoreURL: nil)
        #expect(state.isShowingStorageNotice == true)
    }

    @Test func appStateShowsNoticeForInMemoryFallback() {
        let state = AppState()
        state.storeOutcome = .inMemoryFallback
        #expect(state.isShowingStorageNotice == true)
    }

    @Test func dismissingStorageNoticeHidesIt() {
        let state = AppState()
        state.storeOutcome = .inMemoryFallback
        #expect(state.isShowingStorageNotice == true)

        state.hasDismissedStorageNotice = true
        #expect(state.isShowingStorageNotice == false)
        // The underlying outcome is unchanged — only the notice is dismissed.
        #expect(state.storeOutcome == .inMemoryFallback)
    }

    // MARK: - Factory result

    @Test func makeReturnsUsableContainerWithReportedOutcome() {
        let result = ModelContainerFactory.make()
        // Whatever happened, the app must get a working container and an
        // explicit statement about how it was opened.
        #expect(result.container.schema == ModelContainerFactory.schema)
        #expect(
            result.outcome == .persistent
                || result.outcome == .inMemoryFallback
                || {
                    if case .recoveredFresh = result.outcome { return true }
                    return false
                }()
        )
    }
}
