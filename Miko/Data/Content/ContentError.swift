import Foundation

/// Errors produced by the content pipeline (loading, validation, importing).
enum ContentError: Error, LocalizedError, Equatable {
    case missingFile(String)
    case decoding(String, String)
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let name):
            return "Missing content file: \(name)"
        case .decoding(let name, let reason):
            return "Failed to decode \(name): \(reason)"
        case .validation(let message):
            return message
        }
    }
}
