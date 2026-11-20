import Foundation

struct LessonContentDTO: Codable, Equatable {
    let key: String
    let orderIndex: Int
    let titleKey: String
    let kind: LessonKind
    let unitKey: String
    let vocabularyKeys: [String]
    let grammarKeys: [String]
    let exercises: [ExerciseContentDTO]
}