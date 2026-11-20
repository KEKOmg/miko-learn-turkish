import Foundation
import SwiftData

@Model
final class DailyGoal {
    @Attribute(.unique) var id: UUID
    var xpTarget: Int
    var xpEarnedToday: Int
    var date: Date

    var user: UserProfile?

    var isReached: Bool { xpEarnedToday >= xpTarget }

    init(
        id: UUID = UUID(),
        xpTarget: Int = 50,
        xpEarnedToday: Int = 0,
        date: Date = .now,
        user: UserProfile? = nil
    ) {
        self.id = id
        self.xpTarget = xpTarget
        self.xpEarnedToday = xpEarnedToday
        self.date = date
        self.user = user
    }
}