import Foundation

struct LevelContentDTO: Codable, Equatable {
    let key: String
    let cefr: CEFRLevel
    let orderIndex: Int
    let unitKeys: [String]
}