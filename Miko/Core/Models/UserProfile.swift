import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var username: String
    var avatar: String
    var createdAt: Date

    var activeCourse: Course?
    var progress: UserProgress?
    var settings: UserSettings?
    var hearts: Hearts?

    init(
        id: UUID = UUID(),
        username: String = "",
        avatar: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.username = username
        self.avatar = avatar
        self.createdAt = createdAt
    }
}