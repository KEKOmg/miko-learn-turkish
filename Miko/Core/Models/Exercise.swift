import Foundation
import SwiftData

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var orderIndex: Int
    var typeRaw: String
    var promptKey: String
    var promptText: String
    var payloadData: Data?
    var correctAnswerText: String
    var acceptedAnswers: [String]
    var hintKey: String

    @Relationship(inverse: \VocabularyItem.exercises)
    var vocabulary: [VocabularyItem] = []

    var lesson: Lesson?

    var type: ExerciseType {
        get { ExerciseType(rawValue: typeRaw) ?? .multipleChoice }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        key: String,
        orderIndex: Int,
        type: ExerciseType,
        promptKey: String = "",
        promptText: String = "",
        payloadData: Data? = nil,
        correctAnswerText: String = "",
        acceptedAnswers: [String] = [],
        hintKey: String = "",
        lesson: Lesson? = nil
    ) {
        self.id = id
        self.key = key
        self.orderIndex = orderIndex
        self.typeRaw = type.rawValue
        self.promptKey = promptKey
        self.promptText = promptText
        self.payloadData = payloadData
        self.correctAnswerText = correctAnswerText
        self.acceptedAnswers = acceptedAnswers
        self.hintKey = hintKey
        self.lesson = lesson
    }
}

extension Exercise: KeyedContent {}
