import Foundation
import SwiftData

@Model
final class ExerciseProgress {
    @Attribute(.unique) var id: UUID
    var correctCount: Int
    var incorrectCount: Int
    var lastResult: Bool
    var lastAnsweredAt: Date?
    var reviewDueAt: Date?

    var user: UserProfile?
    var exercise: Exercise?

    init(
        id: UUID = UUID(),
        correctCount: Int = 0,
        incorrectCount: Int = 0,
        lastResult: Bool = false,
        lastAnsweredAt: Date? = nil,
        reviewDueAt: Date? = nil,
        user: UserProfile? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.correctCount = correctCount
        self.incorrectCount = incorrectCount
        self.lastResult = lastResult
        self.lastAnsweredAt = lastAnsweredAt
        self.reviewDueAt = reviewDueAt
        self.user = user
        self.exercise = exercise
    }
}