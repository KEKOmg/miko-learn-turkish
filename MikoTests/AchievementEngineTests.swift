import Foundation
import Testing
@testable import Miko

/// Pure-logic tests for `AchievementEngine`: threshold evaluation and
/// progress calculation across all four condition types. No SwiftData.
struct AchievementEngineTests {

    private let state = AchievementEngine.State(
        xp: 120, currentStreak: 7, totalLessonsCompleted: 3, perfectLessonCount: 2
    )

    @Test func lessonsCompletedThresholdMet() {
        let entry = AchievementCatalog.entries.first { $0.key == "first_lesson" }!
        #expect(AchievementEngine.isEarned(entry, state: state) == true)
    }

    @Test func lessons_10NotMet() {
        let entry = AchievementCatalog.entries.first { $0.key == "lessons_10" }!
        #expect(AchievementEngine.isEarned(entry, state: state) == false)
        #expect(abs(AchievementEngine.progress(entry, state: state) - 0.3) < 0.0001)
    }

    @Test func streak7Met() {
        let entry = AchievementCatalog.entries.first { $0.key == "streak_7" }!
        #expect(AchievementEngine.isEarned(entry, state: state) == true)
        #expect(AchievementEngine.progress(entry, state: state) == 1)
    }

    @Test func streak30NotMet() {
        let entry = AchievementCatalog.entries.first { $0.key == "streak_30" }!
        #expect(AchievementEngine.isEarned(entry, state: state) == false)
    }

    @Test func xp100Met() {
        let entry = AchievementCatalog.entries.first { $0.key == "xp_100" }!
        #expect(AchievementEngine.isEarned(entry, state: state) == true)
    }

    @Test func xp1000NotMet() {
        let entry = AchievementCatalog.entries.first { $0.key == "xp_1000" }!
        #expect(AchievementEngine.isEarned(entry, state: state) == false)
        #expect(abs(AchievementEngine.progress(entry, state: state) - 0.12) < 0.0001)
    }

    @Test func perfectLessonMet() {
        let entry = AchievementCatalog.entries.first { $0.key == "perfect_lesson" }!
        #expect(AchievementEngine.isEarned(entry, state: state) == true)
    }

    @Test func evaluateAllReturnsEveryCatalogEntry() {
        let result = AchievementEngine.evaluateAll(state: state)
        #expect(result.count == AchievementCatalog.entries.count)
        for entry in AchievementCatalog.entries {
            #expect(result[entry.key] != nil)
        }
    }

    @Test func newlyEarnedKeysExcludesAlreadyEarned() {
        let already: Set<String> = ["first_lesson", "streak_7"]
        let new = AchievementEngine.newlyEarnedKeys(state: state, alreadyEarned: already)
        #expect(!new.contains("first_lesson"))
        #expect(!new.contains("streak_7"))
        #expect(new.contains("xp_100"))
        #expect(new.contains("perfect_lesson"))
    }

    @Test func catalogHasSevenEntries() {
        #expect(AchievementCatalog.entries.count == 7)
    }

    @Test func conditionTypeInitFromRawRoundtrips() {
        for type in AchievementConditionType.allCases {
            #expect(AchievementConditionType(raw: type.rawValue) == type)
        }
    }

    @Test func conditionTypeInitReturnsNilForUnknown() {
        #expect(AchievementConditionType(raw: "unknown") == nil)
    }
}
