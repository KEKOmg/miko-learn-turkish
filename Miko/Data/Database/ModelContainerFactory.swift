import Foundation
import SwiftData

enum ModelContainerFactory {

    enum ContainerError: Error {
        case initializationFailed(Error)
    }

    /// How the store backing the app was ultimately opened.
    ///
    /// A persistent-store failure must never be silently downgraded to
    /// in-memory operation: the UI needs to tell the user when their progress
    /// is not being saved, or when a damaged store was set aside.
    enum StoreOutcome: Equatable {
        /// The on-disk store opened normally. Progress persists.
        case persistent

        /// The previous store could not be opened, so it was preserved
        /// alongside a newly created empty store. Progress persists from now
        /// on, but earlier data is not visible.
        /// `preservedStoreURL` points at the renamed original.
        case recoveredFresh(preservedStoreURL: URL?)

        /// Neither the original nor a fresh on-disk store could be opened.
        /// The app runs on a temporary in-memory store and **nothing is
        /// saved**. This is the only acceptable data-loss state and must be
        /// surfaced prominently.
        case inMemoryFallback

        /// True when writes are not being persisted to disk.
        var isEphemeral: Bool { self == .inMemoryFallback }

        /// True when the user should be told something happened to their data.
        var requiresUserNotice: Bool {
            switch self {
            case .persistent: return false
            case .recoveredFresh, .inMemoryFallback: return true
            }
        }
    }

    /// The container plus how it was obtained.
    struct MakeResult {
        let container: ModelContainer
        let outcome: StoreOutcome
    }

    /// The frozen v1 schema, used by both the production container and tests
    /// so they can never drift apart.
    static var schema: Schema { Schema(versionedSchema: SchemaV1.self) }

    /// Creates the production `ModelContainer`.
    ///
    /// Recovery hierarchy:
    /// 1. Open the persistent store normally.
    /// 2. If that fails, **preserve** the existing store by renaming it
    ///    (never delete it) and create a fresh persistent store.
    /// 3. If that also fails, fall back to an in-memory store and report it.
    ///
    /// When the launch argument `-UITestReset` is present (set by UI tests),
    /// an in-memory store is used so every test run starts with a clean
    /// database — no completions or progress from previous runs.
    static func make() -> MakeResult {
        let schema = Self.schema

        let isUITestReset = ProcessInfo.processInfo.arguments.contains("-UITestReset")
        if isUITestReset {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: DatabaseMigrationPlan.self,
                    configurations: [config]
                )
                // UI tests intentionally run on a clean in-memory store; this
                // is expected behaviour, not a recovery state.
                return MakeResult(container: container, outcome: .persistent)
            } catch {
                fatalError("In-memory ModelContainer for UI tests failed: \(error)")
            }
        }

        // 1. Normal path.
        do {
            let configuration = ModelConfiguration(schema: schema)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: DatabaseMigrationPlan.self,
                configurations: [configuration]
            )
            return MakeResult(container: container, outcome: .persistent)
        } catch {
            // 2. Preserve the unreadable store and try a fresh one.
            let preservedURL = preserveExistingStore()
            do {
                let configuration = ModelConfiguration(schema: schema)
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: DatabaseMigrationPlan.self,
                    configurations: [configuration]
                )
                return MakeResult(
                    container: container,
                    outcome: .recoveredFresh(preservedStoreURL: preservedURL)
                )
            } catch {
                // 3. Last resort: ephemeral storage, explicitly reported.
                return MakeResult(
                    container: fallbackInMemory(schema: schema, originalError: error),
                    outcome: .inMemoryFallback
                )
            }
        }
    }

    // MARK: - Store preservation

    /// Default on-disk location SwiftData uses for the unnamed configuration.
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// Renames the existing store (and its SQLite sidecar files) out of the
    /// way so a fresh store can be created in its place.
    ///
    /// The damaged store is **never deleted** — it is moved aside with a
    /// `.corrupt-<timestamp>` suffix so it can be recovered or inspected
    /// later. Returns the new location of the preserved main store file, or
    /// `nil` when there was nothing to preserve.
    @discardableResult
    static func preserveExistingStore(
        at storeURL: URL? = nil,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> URL? {
        let mainStoreURL = storeURL ?? defaultStoreURL
        guard fileManager.fileExists(atPath: mainStoreURL.path) else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        // Colons are legal on APFS but awkward in paths; strip them.
        let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        let suffix = "corrupt-\(stamp)"

        var preservedMainURL: URL?

        // SwiftData/SQLite keeps -wal and -shm sidecars next to the store;
        // move them together so the preserved copy stays consistent.
        for sidecar in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: mainStoreURL.path + sidecar)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            let destination = URL(fileURLWithPath: "\(mainStoreURL.path).\(suffix)\(sidecar)")
            do {
                try fileManager.moveItem(at: source, to: destination)
                if sidecar.isEmpty { preservedMainURL = destination }
            } catch {
                // Preservation is best-effort: if the move fails we still try
                // to open a fresh store rather than destroying anything.
                continue
            }
        }

        return preservedMainURL
    }

    /// In-memory fallback so the app remains usable even if the persistent
    /// store is corrupted or unreadable. Callers must surface this state —
    /// nothing written here survives relaunch.
    private static func fallbackInMemory(
        schema: Schema,
        originalError: Error
    ) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: DatabaseMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError(
                "ModelContainer cannot be created even in-memory. " +
                "Original error: \(originalError). In-memory error: \(error)."
            )
        }
    }
}
