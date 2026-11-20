import Foundation

// MARK: - Payloads with structured data

struct MultipleChoicePayload: Codable, Equatable {
    let options: [String]
    let correctIndex: Int
}

struct BuildSentencePayload: Codable, Equatable {
    let wordBank: [String]
    let sentenceWords: [String]
}

struct MatchPairsPayload: Codable, Equatable {
    let pairs: [MatchPair]
}

struct MatchPair: Codable, Equatable {
    let source: String
    let target: String
}

struct FillBlankPayload: Codable, Equatable {
    let template: String
    let blank: String
    let options: [String]

    /// Canonical placeholder written into seed templates.
    static let canonicalPlaceholder = "____"

    /// Minimum run of underscores accepted as a blank placeholder. Rendering
    /// is deliberately tolerant (3+) so a seed authored with a slightly
    /// different run length still shows a blank instead of silently rendering
    /// the placeholder as literal text. `ContentValidator` remains strict and
    /// requires the canonical form.
    static let minimumPlaceholderLength = 3

    /// Splits `template` around its underscore placeholder.
    ///
    /// Returns `nil` when the template contains no run of at least
    /// `minimumPlaceholderLength` underscores.
    static func split(template: String) -> (prefix: String, suffix: String)? {
        var runStart: String.Index?
        var index = template.startIndex

        while index < template.endIndex {
            if template[index] == "_" {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                if template.distance(from: start, to: index) >= minimumPlaceholderLength {
                    return (String(template[template.startIndex..<start]), String(template[index...]))
                }
                runStart = nil
            }
            index = template.index(after: index)
        }

        // Placeholder runs to the end of the template.
        if let start = runStart,
           template.distance(from: start, to: template.endIndex) >= minimumPlaceholderLength {
            return (String(template[template.startIndex..<start]), "")
        }
        return nil
    }

    /// True when the template contains a usable blank placeholder.
    static func hasPlaceholder(in template: String) -> Bool {
        split(template: template) != nil
    }
}

/// Listening comprehension carries its own correct answer index. It must NOT
/// be validated through `MultipleChoicePayload` — the two payload shapes are
/// distinct and decoding one as the other silently fails, which would mark
/// every listening answer incorrect.
struct ListeningComprehensionPayload: Codable, Equatable {
    let audioFileName: String
    let transcript: String
    let options: [String]
    let correctIndex: Int
}

// MARK: - Minimal payloads (data lives in Exercise fields)

/// Translate-word exercises use `Exercise.promptText` (source) and
/// `Exercise.correctAnswerText` / `acceptedAnswers` (target). No extra
/// payload is required.
struct TranslateWordPayload: Codable, Equatable {}

/// Translate-sentence exercises follow the same pattern as translate-word,
/// operating on full sentences.
struct TranslateSentencePayload: Codable, Equatable {}

/// Pronunciation exercises carry the text to pronounce in `promptText`.
/// The `SpeechProviding` protocol handles recognition.
struct PronunciationPayload: Codable, Equatable {}

/// Vocabulary review exercises display a vocabulary card with source/target
/// text and optional audio. The vocabulary items come from
/// `Exercise.vocabulary`.
struct VocabularyReviewPayload: Codable, Equatable {}
