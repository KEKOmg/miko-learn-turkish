import Foundation
import SwiftData

@Model
final class LessonProgress {
    @Attribute(.unique) var id: UUID
    var statusRaw: String
    var bestAccuracy: Double
    var attempts: Int
    var lastCompletedAt: Date?

    var user: UserProfile?
    var lesson: Lesson?

    var status: LessonProgressStatus {
        get { LessonProgressStatus(rawValue: statusRaw) ?? .locked }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        status: LessonProgressStatus = .locked,
        bestAccuracy: Double = 0,
        attempts: Int = 0,
        lastCompletedAt: Date? = nil,
        user: UserProfile? = nil,
        lesson: Lesson? = nil
    ) {
        self.id = id
        self.statusRaw = status.rawValue
        self.bestAccuracy = bestAccuracy
        self.attempts = attempts
        self.lastCompletedAt = lastCompletedAt
        self.user = user
        self.lesson = lesson
    }
}