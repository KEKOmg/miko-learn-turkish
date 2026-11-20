import Foundation
import SwiftData
@testable import Miko

enum ContentTestSupport {

    private static let containerLock = NSLock()

    static func makeInMemoryContainer() throws -> ModelContainer {
        containerLock.lock()
        defer { containerLock.unlock() }

        // Use the same frozen, versioned schema as production so tests can
        // never silently diverge from the shipped store layout.
        //
        // A unique per-container name keeps each in-memory store isolated:
        // naming the configuration without one makes SwiftData reuse a single
        // shared store across concurrently running tests.
        let schema = ModelContainerFactory.schema
        let config = ModelConfiguration(
            "test-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: DatabaseMigrationPlan.self,
            configurations: [config]
        )
    }

    static func loadBundle() throws -> ContentBundle {
        let bundle = Bundle(for: Course.self)
        return try BundleContentSource(bundle: bundle).load()
    }
}
