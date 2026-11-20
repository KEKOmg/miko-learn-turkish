import Foundation

struct ExerciseContentDTO: Codable, Equatable {
    let key: String
    let type: ExerciseType
    let orderIndex: Int
    let promptText: String
    let promptKey: String
    let hintKey: String
    let correctAnswerText: String
    let acceptedAnswers: [String]
    let vocabularyKeys: [String]
    let payload: JSONValue?
}