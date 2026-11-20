import Foundation

enum CEFRLevel: String, Codable, CaseIterable {
    case a1
    case a2
    case b1
    case b2

    var displayNameKey: String {
        switch self {
        case .a1: return "level.a1"
        case .a2: return "level.a2"
        case .b1: return "level.b1"
        case .b2: return "level.b2"
        }
    }
}