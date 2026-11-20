import Foundation

struct UnitContentDTO: Codable, Equatable {
    let key: String
    let orderIndex: Int
    let titleKey: String
    let theme: String
    let summaryKey: String
    let levelKey: String
    let lessonKeys: [String]
}