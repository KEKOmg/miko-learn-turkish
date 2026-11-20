import Foundation
import SwiftData

/// Persistent heart economy for a user. A single row per `UserProfile`,
/// created by `UserBootstrap` on first launch. Regeneration is computed from
/// `lastRegeneratedAt` on demand — no background timer required.
@Model
final class Hearts {
    @Attribute(.unique) var id: UUID
    var currentHearts: Int
    var maxHearts: Int
    var lastRegeneratedAt: Date

    var user: UserProfile?

    init(
        id: UUID = UUID(),
        currentHearts: Int = 5,
        maxHearts: Int = 5,
        lastRegeneratedAt: Date = .now,
        user: UserProfile? = nil
    ) {
        self.id = id
        self.currentHearts = currentHearts
        self.maxHearts = maxHearts
        self.lastRegeneratedAt = lastRegeneratedAt
        self.user = user
    }
}
