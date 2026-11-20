import Foundation

/// Validates a user's answer against an exercise.
///
/// Implementations must NOT hardcode correct answers — they use the
/// `correctAnswerText`, `acceptedAnswers`, and payload data from the
/// `Exercise` model.
protocol ExerciseValidating {
    func validate(answer: ExerciseAnswer, exercise: Exercise) -> ExerciseResult
}

/// Central entry point: dispatches to the correct validator based on
/// `exercise.type`.
struct ExerciseValidator: ExerciseValidating {

    static let shared = ExerciseValidator()

    init() {}

    func validate(answer: ExerciseAnswer, exercise: Exercise) -> ExerciseResult {
        switch exercise.type {
        case .multipleChoice:
            return MultipleChoiceValidator().validate(answer: answer, exercise: exercise)
        case .translateWord:
            return TextAnswerValidator().validate(answer: answer, exercise: exercise)
        case .translateSentence:
            return TextAnswerValidator().validate(answer: answer, exercise: exercise)
        case .buildSentence:
            return BuildSentenceValidator().validate(answer: answer, exercise: exercise)
        case .matchPairs:
            return MatchPairsValidator().validate(answer: answer, exercise: exercise)
        case .fillBlank:
            return TextAnswerValidator().validate(answer: answer, exercise: exercise)
        case .listeningComprehension:
            return ListeningValidator().validate(answer: answer, exercise: exercise)
        case .pronunciation:
            return TextAnswerValidator().validate(answer: answer, exercise: exercise)
        case .vocabularyReview:
            return VocabularyReviewValidator().validate(answer: answer, exercise: exercise)
        }
    }
}

// MARK: - Text-based validator (translateWord, translateSentence, fillBlank, pronunciation)

struct TextAnswerValidator: ExerciseValidating {

    func validate(answer: ExerciseAnswer, exercise: Exercise) -> ExerciseResult {
        switch answer {
        case .text(let userText):
            return validateText(userText, exercise: exercise)
        default:
            return .incorrect(canonicalAnswer: exercise.correctAnswerText)
        }
    }

    private func validateText(_ userText: String, exercise: Exercise) -> ExerciseResult {
        let candidates = [exercise.correctAnswerText] + exercise.acceptedAnswers
        let normalizedUser = TurkishTextNormalizer.normalize(userText)

        for candidate in candidates {
            if TurkishTextNormalizer.normalize(candidate) == normalizedUser {
                return .correct
            }
        }

        let lenientUser = TurkishTextNormalizer.normalizeLenient(userText)
        for candidate in candidates {
            if TurkishTextNormalizer.normalizeLenient(candidate) == lenientUser {
                return .correct
            }
        }

        return .incorrect(canonicalAnswer: exercise.correctAnswerText)
    }
}

// MARK: - Listening comprehension validator

/// Validates listening exercises against `ListeningComprehensionPayload`.
///
/// Deliberately separate from `MultipleChoiceValidator`: the listening payload
/// has its own shape (`audioFileName` / `transcript` / `options` /
/// `correctIndex`), so reusing the multiple-choice decoder would fail and mark
/// every answer incorrect.
struct ListeningValidator: ExerciseValidating {

    func validate(answer: ExerciseAnswer, exercise: Exercise) -> ExerciseResult {
        guard let payloadData = exercise.payloadData,
              let payload = try? JSONDecoder().decode(ListeningComprehensionPayload.self, from: payloadData) else {
            return .incorrect(canonicalAnswer: exercise.correctAnswerText)
        }

        switch answer {
        case .index(let selectedIndex):
            if selectedIndex == payload.correctIndex {
                return .correct
            }
            let correctOption = payload.options.indices.contains(payload.correctIndex)
                ? payload.options[payload.correctIndex]
                : exercise.correctAnswerText
            return .incorrect(canonicalAnswer: correctOption)

        default:
            return .incorrect(canonicalAnswer: exercise.correctAnswerText)
        }
    }
}

// MARK: - Multiple choice validator

struct MultipleChoiceValidator: ExerciseValidating {

    func validate(answer: ExerciseAnswer, exercise: Exercise) -> ExerciseResult {
        guard let payloadData = exercise.payloadData,
              let payload = try? JSONDecoder().decode(MultipleChoicePayload.self, from: payloadData) else {
            return .incorrect(canonicalAnswer: exercise.correctAnswerText)
        }

        switch answer {
        case .index(let selectedIndex):
            if selectedIndex == payload.correctIndex {
                return .correct
            }
            let correctOption = payload.options.indices.contains(payload.correctIndex)
                ? payload.options[payload.correctIndex]
                : exercise.correctAnswerText
            return .incorrect(canonicalAnswer: correctOption)

        default:
            return .incorrect(canonicalAnswer: exercise.correctAnswerText)
        }
    }
}

// MARK: - Build sentence validator

struct BuildSentenceValidator: ExerciseValidating {

    func validate(answer: ExerciseAnswer, exercise: Exercise) -> ExerciseResult {
        guard let payloadData = exercise.payloadData,
              let payload = try? JSONDecoder().decode(BuildSentencePayload.self, from: payloadData) else {
            return .incorrect(canonicalAnswer: exercise.correctAnswerText)
        }

        switch answer {
        case .wordOrder(let userWords):
            let correctWords = payload.sentenceWords
            if userWords.count != correctWords.count {
                return .incorrect(canonicalAnswer: correctWords.joined(separator: " "))
            }

            let normalizedUser = userWords.map { TurkishTextNormalizer.normalize($0) }
            let normalizedCorrect = correctWords.map { TurkishTextNormalizer.normalize($0) }

            if normalizedUser == normalizedCorrect {
                return .correct
            }

            let lenientUser = userWords.map { TurkishTextNormalizer.normalizeLenient($0) }
            let lenientCorrect = correctWords.map { TurkishTextNormalizer.normalizeLenient($0) }

            if lenientUser == lenientCorrect {
                return .correct
            }

            return .incorrect(canonicalAnswer: correctWords.joined(separator: " "))

        default:
            return .incorrect(canonicalAnswer: exercise.correctAnswerText)
        }
    }
}

// MARK: - Match pairs validator

struct MatchPairsValidator: ExerciseValidating {

    func validate(answer: ExerciseAnswer, exercise: Exercise) -> ExerciseResult {
        guard let payloadData = exercise.payloadData,
              let payload = try? JSONDecoder().decode(MatchPairsPayload.self, from: payloadData) else {
            return .incorrect(canonicalAnswer: exercise.correctAnswerText)
        }

        switch answer {
        case .matchedPairs(let userPairs):
            let correctPairs = payload.pairs
            if userPairs.count != correctPairs.count {
                return .incorrect(canonicalAnswer: "")
            }

            let normalizedCorrect = Set(correctPairs.map {
                "\(TurkishTextNormalizer.normalize($0.source))||\(TurkishTextNormalizer.normalize($0.target))"
            })

            for userPair in userPairs {
                let normalizedUser = "\(TurkishTextNormalizer.normalize(userPair.0))||\(TurkishTextNormalizer.normalize(userPair.1))"
                if !normalizedCorrect.contains(normalizedUser) {
                    return .incorrect(canonicalAnswer: "")
                }
            }

            return .correct

        default:
            return .incorrect(canonicalAnswer: "")
        }
    }
}

// MARK: - Vocabulary review validator (always correct on dismiss)

struct VocabularyReviewValidator: ExerciseValidating {

    func validate(answer: ExerciseAnswer, exercise: Exercise) -> ExerciseResult {
        switch answer {
        case .acknowledged:
            return .correct
        default:
            return .correct
        }
    }
}
