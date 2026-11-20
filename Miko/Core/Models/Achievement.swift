import Foundation
import SwiftData

@Model
final class Achievement {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var titleKey: String
    var descriptionKey: String
    var conditionTypeRaw: String
    var conditionValue: Int
    var icon: String

    init(
        id: UUID = UUID(),
        key: String,
        titleKey: String,
        descriptionKey: String,
        conditionTypeRaw: String,
        conditionValue: Int,
        icon: String
    ) {
        self.id = id
        self.key = key
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.conditionTypeRaw = conditionTypeRaw
        self.conditionValue = conditionValue
        self.icon = icon
    }
}