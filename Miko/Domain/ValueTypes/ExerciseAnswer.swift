import Foundation

/// The user's answer to an exercise, abstracted so validators can work
/// uniformly across exercise types.
enum ExerciseAnswer {
    /// Free-text answer (translateWord, translateSentence, fillBlank, pronunciation).
    case text(String)
    /// Selected option index (multipleChoice, listening).
    case index(Int)
    /// Ordered list of words (buildSentence).
    case wordOrder([String])
    /// Matched pairs: array of (source, target) tuples (matchPairs).
    case matchedPairs([(String, String)])
    /// No input required (vocabularyReview — always "correct" on dismiss).
    case acknowledged
}

/// The outcome of validating an answer.
enum ExerciseResult: Equatable {
    case correct
    case incorrect(canonicalAnswer: String)
    /// Recognition could not run (permission denied or no microphone).
    /// This is neither a wrong answer nor an XP-earning correct answer.
    case skipped
}
