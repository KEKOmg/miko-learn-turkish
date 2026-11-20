import Foundation
import SwiftData

@Model
final class Unit {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var orderIndex: Int
    var titleKey: String
    var theme: String
    var summaryKey: String
    var isLocked: Bool

    @Relationship(deleteRule: .cascade, inverse: \Lesson.unit)
    var lessons: [Lesson] = []

    var level: Level?

    init(
        id: UUID = UUID(),
        key: String,
        orderIndex: Int,
        titleKey: String,
        theme: String,
        summaryKey: String,
        isLocked: Bool = true,
        level: Level? = nil
    ) {
        self.id = id
        self.key = key
        self.orderIndex = orderIndex
        self.titleKey = titleKey
        self.theme = theme
        self.summaryKey = summaryKey
        self.isLocked = isLocked
        self.level = level
    }
}

extension Unit: KeyedContent {}