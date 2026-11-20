import Foundation

enum LessonKind: String, Codable, CaseIterable {
    case skill
    case review
    case grammar
    case quiz
}