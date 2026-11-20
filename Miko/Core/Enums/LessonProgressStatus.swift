import Foundation

enum LessonProgressStatus: String, Codable, CaseIterable {
    case locked
    case unlocked
    case inProgress
    case completed
}