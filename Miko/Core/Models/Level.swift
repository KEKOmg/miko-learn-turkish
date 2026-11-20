import Foundation
import SwiftData

@Model
final class Level {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var cefrRaw: String
    var orderIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \Unit.level)
    var units: [Unit] = []

    var course: Course?

    var cefr: CEFRLevel {
        get { CEFRLevel(rawValue: cefrRaw) ?? .a1 }
        set { cefrRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        key: String,
        cefr: CEFRLevel,
        orderIndex: Int,
        course: Course? = nil
    ) {
        self.id = id
        self.key = key
        self.cefrRaw = cefr.rawValue
        self.orderIndex = orderIndex
        self.course = course
    }
}

extension Level: KeyedContent {}