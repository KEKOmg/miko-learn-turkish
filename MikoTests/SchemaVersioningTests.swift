import Foundation
import SwiftData
import Testing
@testable import Miko

/// Guards the frozen v1 SwiftData schema (CRITICAL-2).
///
/// `SchemaV1` is the shipped store layout. These tests fail loudly if a model
/// is added or removed without introducing a new versioned schema and a
/// corresponding migration stage.
@Suite(.serialized)
struct SchemaVersioningTests {

    /// The exact model set frozen as v1.
    private var expectedModelNames: Set<String> {
        [
            "Language", "Course", "Level", "Unit", "Lesson", "Exercise",
            "VocabularyItem", "GrammarTopic", "UserProfile", "UserProgress",
            "LessonProgress", "ExerciseProgress", "Achievement",
            "UserAchievement", "DailyGoal", "Streak", "UserSettings", "Hearts"
        ]
    }

    @Test func schemaV1ContainsExactlyEighteenModels() {
        #expect(SchemaV1.models.count == 18)
    }

    @Test func schemaV1ContainsTheExpectedModels() {
        let actual = Set(SchemaV1.models.map { String(describing: $0) })
        #expect(actual == expectedModelNames)
    }

    @Test func schemaV1HasNoDuplicateModels() {
        let names = SchemaV1.models.map { String(describing: $0) }
        #expect(Set(names).count == names.count)
    }

    @Test func schemaV1VersionIdentifierIsOneZeroZero() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    // MARK: - Migration plan wiring

    @Test func migrationPlanRegistersSchemaV1() {
        let names = DatabaseMigrationPlan.schemas.map { String(describing: $0) }
        #expect(names.contains("SchemaV1"))
    }

    @Test func migrationPlanHasNoStagesWhileOnlyV1Exists() {
        // A single registered schema needs no migration stage. When SchemaV2
        // is added this must be updated together with a MigrationStage.
        #expect(DatabaseMigrationPlan.schemas.count == 1)
        #expect(DatabaseMigrationPlan.stages.isEmpty)
    }

    /// Every schema registered in the plan must be covered by a migration
    /// stage chain: N schemas require N-1 stages.
    @Test func migrationStageCountMatchesSchemaChain() {
        #expect(DatabaseMigrationPlan.stages.count == DatabaseMigrationPlan.schemas.count - 1)
    }

    // MARK: - Production / test container parity

    @Test func factorySchemaIsBuiltFromVersionedSchema() {
        let factorySchema = ModelContainerFactory.schema
        let versioned = Schema(versionedSchema: SchemaV1.self)
        #expect(factorySchema == versioned)
    }

    /// The production container and the test container must use the same
    /// versioned schema, otherwise tests validate a layout that never ships.
    @Test func testContainerUsesSameSchemaAsProduction() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        #expect(container.schema == ModelContainerFactory.schema)
        #expect(container.schema == Schema(versionedSchema: SchemaV1.self))
    }

    @Test func containerSchemaEntityCountMatchesModelCount() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        #expect(container.schema.entities.count == SchemaV1.models.count)
    }

    /// `UserProgress.gems` is part of the frozen v1 schema and must remain
    /// present and persistable.
    @Test func schemaV1IncludesUserProgressGems() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let entity = try #require(
            container.schema.entities.first { $0.name == "UserProgress" }
        )
        #expect(entity.properties.contains { $0.name == "gems" })
    }

    @Test func gemsRoundTripThroughTheVersionedSchema() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)

        let user = UserProfile(username: "tester", avatar: "")
        context.insert(user)
        let progress = UserProgress()
        progress.gems = 42
        progress.user = user
        context.insert(progress)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserProgress>())
        #expect(fetched.first?.gems == 42)
    }
}
