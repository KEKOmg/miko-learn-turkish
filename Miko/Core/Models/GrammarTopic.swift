import Foundation
import SwiftData

@Model
final class GrammarTopic {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var titleKey: String
    var explanationKey: String
    var examples: [String]
    var cefrRaw: String

    @Relationship(deleteRule: .nullify)
    var lessons: [Lesson] = []

    var cefr: CEFRLevel {
        get { CEFRLevel(rawValue: cefrRaw) ?? .a1 }
        set { cefrRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        key: String,
        titleKey: String,
        explanationKey: String,
        examples: [String] = [],
        cefr: CEFRLevel
    ) {
        self.id = id
        self.key = key
        self.titleKey = titleKey
        self.explanationKey = explanationKey
        self.examples = examples
        self.cefrRaw = cefr.rawValue
    }
}

extension GrammarTopic: KeyedContent {}
