import Foundation
import SwiftData

@Model
final class Course {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var titleKey: String
    var version: Int
    var sourceLanguage: Language?
    var targetLanguage: Language?

    @Relationship(deleteRule: .cascade, inverse: \Level.course)
    var levels: [Level] = []

    init(
        id: UUID = UUID(),
        key: String,
        titleKey: String = "",
        version: Int = 1,
        sourceLanguage: Language? = nil,
        targetLanguage: Language? = nil
    ) {
        self.id = id
        self.key = key
        self.titleKey = titleKey
        self.version = version
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

extension Course: KeyedContent {}