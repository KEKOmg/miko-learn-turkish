import Foundation

struct CourseContentDTO: Codable, Equatable {
    let key: String
    let sourceLanguageCode: String
    let targetLanguageCode: String
    let version: Int
    let titleKey: String
}