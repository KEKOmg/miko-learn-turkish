import Foundation

struct GrammarContentDTO: Codable, Equatable {
    let key: String
    let titleKey: String
    let explanationKey: String
    let examples: [String]
    let cefr: CEFRLevel
}