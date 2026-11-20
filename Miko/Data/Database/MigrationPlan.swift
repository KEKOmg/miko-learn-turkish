import Foundation
import SwiftData

/// Migration strategy.
///
/// `SchemaV1` is the frozen v1 production schema. It is registered here so the
/// store is always opened through an explicit, versioned schema rather than an
/// ad-hoc model list.
///
/// Adding a schema change post-ship means:
/// 1. Add a new `SchemaV2` versioned schema (never edit `SchemaV1`).
/// 2. Append it to `schemas`.
/// 3. Add a `MigrationStage` (lightweight or custom) to `stages`.
enum DatabaseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    /// Empty until a `SchemaV2` exists — a single registered schema needs no
    /// migration stage.
    static var stages: [MigrationStage] { [] }
}
