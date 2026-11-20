import Foundation
import SwiftData

@Model
final class Lesson {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var orderIndex: Int
    var titleKey: String
    var kindRaw: String

    @Relationship(deleteRule: .cascade, inverse: \Exercise.lesson)
    var exercises: [Exercise] = []

    // Explicit inverses are required: without them SwiftData degrades shared
    // many-to-many links to "last writer wins", silently detaching vocabulary
    // and grammar topics that are referenced by several lessons or exercises.
    @Relationship(inverse: \VocabularyItem.lessons)
    var vocabulary: [VocabularyItem] = []

    @Relationship(inverse: \GrammarTopic.lessons)
    var grammarTopics: [GrammarTopic] = []

    var unit: Unit?

    var kind: LessonKind {
        get { LessonKind(rawValue: kindRaw) ?? .skill }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        key: String,
        orderIndex: Int,
        titleKey: String,
        kind: LessonKind,
        unit: Unit? = nil
    ) {
        self.id = id
        self.key = key
        self.orderIndex = orderIndex
        self.titleKey = titleKey
        self.kindRaw = kind.rawValue
        self.unit = unit
    }
}

extension Lesson: KeyedContent {}