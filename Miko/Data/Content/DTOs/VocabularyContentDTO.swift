import Foundation

struct VocabularyContentDTO: Codable, Equatable {
    let key: String
    let sourceText: String
    let targetText: String
    let pronunciation: String
    let partOfSpeech: PartOfSpeech
    let cefr: CEFRLevel
    let exampleSource: String
    let exampleTarget: String
    let difficulty: Int
    let imageAsset: String?
    let audioFileName: String?
}