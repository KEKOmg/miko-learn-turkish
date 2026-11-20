import Foundation
import SwiftData

@Model
final class VocabularyItem {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var sourceText: String
    var targetText: String
    var pronunciation: String
    var partOfSpeechRaw: String
    var cefrRaw: String
    var exampleSource: String
    var exampleTarget: String
    var difficulty: Int
    var imageAsset: String?
    var audioFileName: String?

    @Relationship(deleteRule: .nullify)
    var lessons: [Lesson] = []

    @Relationship(deleteRule: .nullify)
    var exercises: [Exercise] = []

    var partOfSpeech: PartOfSpeech {
        get { PartOfSpeech(rawValue: partOfSpeechRaw) ?? .noun }
        set { partOfSpeechRaw = newValue.rawValue }
    }

    var cefr: CEFRLevel {
        get { CEFRLevel(rawValue: cefrRaw) ?? .a1 }
        set { cefrRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        key: String,
        sourceText: String,
        targetText: String,
        pronunciation: String = "",
        partOfSpeech: PartOfSpeech,
        cefr: CEFRLevel,
        exampleSource: String = "",
        exampleTarget: String = "",
        difficulty: Int = 1,
        imageAsset: String? = nil,
        audioFileName: String? = nil
    ) {
        self.id = id
        self.key = key
        self.sourceText = sourceText
        self.targetText = targetText
        self.pronunciation = pronunciation
        self.partOfSpeechRaw = partOfSpeech.rawValue
        self.cefrRaw = cefr.rawValue
        self.exampleSource = exampleSource
        self.exampleTarget = exampleTarget
        self.difficulty = difficulty
        self.imageAsset = imageAsset
        self.audioFileName = audioFileName
    }
}

extension VocabularyItem: KeyedContent {}