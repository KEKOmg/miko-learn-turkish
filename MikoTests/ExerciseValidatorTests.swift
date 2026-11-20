import Foundation
import Testing
@testable import Miko

@Suite(.serialized)
struct ExerciseValidatorTests {

    // MARK: - Helpers

    private func makeExercise(
        type: ExerciseType = .translateWord,
        correctAnswer: String = "Merhaba",
        accepted: [String] = ["merhaba"],
        payload: Codable? = nil as MultipleChoicePayload?
    ) -> Exercise {
        let exercise = Exercise(key: "test", orderIndex: 0, type: type)
        exercise.correctAnswerText = correctAnswer
        exercise.acceptedAnswers = accepted

        if let payload, let data = try? JSONEncoder().encode(payload) {
            exercise.payloadData = data
        }
        return exercise
    }

    private func makeMultipleChoiceExercise(
        options: [String] = ["A", "B", "C"],
        correctIndex: Int = 0,
        correctAnswer: String = "A"
    ) -> Exercise {
        let exercise = Exercise(key: "mc", orderIndex: 0, type: .multipleChoice)
        exercise.correctAnswerText = correctAnswer
        exercise.acceptedAnswers = []
        exercise.payloadData = try? JSONEncoder().encode(
            MultipleChoicePayload(options: options, correctIndex: correctIndex)
        )
        return exercise
    }

    private func makeBuildSentenceExercise(
        wordBank: [String] = ["Ben", "geliyorum"],
        sentenceWords: [String] = ["Ben", "geliyorum"],
        correctAnswer: String = "Ben geliyorum"
    ) -> Exercise {
        let exercise = Exercise(key: "bs", orderIndex: 0, type: .buildSentence)
        exercise.correctAnswerText = correctAnswer
        exercise.acceptedAnswers = []
        exercise.payloadData = try? JSONEncoder().encode(
            BuildSentencePayload(wordBank: wordBank, sentenceWords: sentenceWords)
        )
        return exercise
    }

    private func makeMatchPairsExercise(
        pairs: [(String, String)] = [("Привет", "Merhaba"), ("Пока", "Hoşça kal")]
    ) -> Exercise {
        let exercise = Exercise(key: "mp", orderIndex: 0, type: .matchPairs)
        exercise.correctAnswerText = ""
        exercise.acceptedAnswers = []
        exercise.payloadData = try? JSONEncoder().encode(
            MatchPairsPayload(pairs: pairs.map { MatchPair(source: $0.0, target: $0.1) })
        )
        return exercise
    }

    private func makeFillBlankExercise(
        template: String = "Ben ___ öğrenciyim.",
        blank: String = "bir",
        options: [String] = ["bir", "iki", "üç"]
    ) -> Exercise {
        let exercise = Exercise(key: "fb", orderIndex: 0, type: .fillBlank)
        exercise.correctAnswerText = blank
        exercise.acceptedAnswers = [blank]
        exercise.payloadData = try? JSONEncoder().encode(
            FillBlankPayload(template: template, blank: blank, options: options)
        )
        return exercise
    }

    // MARK: - Text answer (translateWord)

    @Test func correctTextAnswer() {
        let exercise = makeExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("Merhaba"), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func correctTextAnswerCaseInsensitive() {
        let exercise = makeExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("merhaba"), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func correctTextAnswerWithWhitespace() {
        let exercise = makeExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("  Merhaba  "), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func incorrectTextAnswer() {
        let exercise = makeExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("Güle güle"), exercise: exercise)
        if case .incorrect(let canonical) = result {
            #expect(canonical == "Merhaba")
        } else {
            #expect(Bool(false), "Expected incorrect")
        }
    }

    @Test func acceptedAnswerMatch() {
        let exercise = makeExercise(correctAnswer: "Güle güle", accepted: ["gule gule", "Güle Güle"])
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("gule gule"), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func turkishDiacriticLenientMatch() {
        let exercise = makeExercise(correctAnswer: "şğçöü", accepted: [])
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("sgcou"), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func turkishIVsI() {
        let exercise = makeExercise(correctAnswer: "Istanbul", accepted: [])
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("ıstanbul"), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func turkishDottedI() {
        let exercise = makeExercise(correctAnswer: "İstanbul", accepted: [])
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("istanbul"), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func dotlessIIsNotAcceptedForDottedI() {
        let exercise = makeExercise(correctAnswer: "İstanbul", accepted: [])
        #expect(ExerciseValidator().validate(answer: .text("ıstanbul"), exercise: exercise)
                == .incorrect(canonicalAnswer: "İstanbul"))
    }

    @Test func dottedIIsNotAcceptedForDotlessI() {
        let exercise = makeExercise(correctAnswer: "Nasılsın", accepted: [])
        #expect(ExerciseValidator().validate(answer: .text("Nasilsi n"), exercise: exercise)
                == .incorrect(canonicalAnswer: "Nasılsın"))
        #expect(ExerciseValidator().validate(answer: .text("Nasilsin"), exercise: exercise)
                == .incorrect(canonicalAnswer: "Nasılsın"))
    }

    @Test func trailingPunctuationIgnored() {
        let exercise = makeExercise(correctAnswer: "Merhaba!", accepted: [])
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("Merhaba"), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func emptyTextAnswerIsIncorrect() {
        let exercise = makeExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text(""), exercise: exercise)
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect for empty answer")
        }
    }

    // MARK: - Multiple choice

    @Test func multipleChoiceCorrectIndex() {
        let exercise = makeMultipleChoiceExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .index(0), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func multipleChoiceIncorrectIndex() {
        let exercise = makeMultipleChoiceExercise(correctIndex: 0)
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .index(1), exercise: exercise)
        if case .incorrect(let canonical) = result {
            #expect(canonical == "A")
        } else {
            #expect(Bool(false), "Expected incorrect")
        }
    }

    @Test func multipleChoiceWrongAnswerType() {
        let exercise = makeMultipleChoiceExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("A"), exercise: exercise)
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect for text answer to MC")
        }
    }

    // MARK: - Build sentence

    @Test func buildSentenceCorrectOrder() {
        let exercise = makeBuildSentenceExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .wordOrder(["Ben", "geliyorum"]), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func buildSentenceWrongOrder() {
        let exercise = makeBuildSentenceExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .wordOrder(["geliyorum", "Ben"]), exercise: exercise)
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect for wrong word order")
        }
    }

    @Test func buildSentenceMissingWord() {
        let exercise = makeBuildSentenceExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .wordOrder(["Ben"]), exercise: exercise)
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect for missing word")
        }
    }

    @Test func buildSentenceCaseInsensitive() {
        let exercise = makeBuildSentenceExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .wordOrder(["ben", "GELİYORUM"]), exercise: exercise)
        #expect(result == .correct)
    }

    // MARK: - Match pairs

    @Test func matchPairsAllCorrect() {
        let exercise = makeMatchPairsExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(
            answer: .matchedPairs([("Привет", "Merhaba"), ("Пока", "Hoşça kal")]),
            exercise: exercise
        )
        #expect(result == .correct)
    }

    @Test func matchPairsOneWrong() {
        let exercise = makeMatchPairsExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(
            answer: .matchedPairs([("Привет", "Hoşça kal")]),
            exercise: exercise
        )
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect for wrong pair")
        }
    }

    @Test func matchPairsIncomplete() {
        let exercise = makeMatchPairsExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(
            answer: .matchedPairs([("Привет", "Merhaba")]),
            exercise: exercise
        )
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect for incomplete pairs")
        }
    }

    // MARK: - Fill blank

    @Test func fillBlankCorrect() {
        let exercise = makeFillBlankExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("bir"), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func fillBlankIncorrect() {
        let exercise = makeFillBlankExercise()
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .text("iki"), exercise: exercise)
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect")
        }
    }

    // MARK: - Vocabulary review

    @Test func vocabularyReviewAlwaysCorrect() {
        let exercise = Exercise(key: "vr", orderIndex: 0, type: .vocabularyReview)
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .acknowledged, exercise: exercise)
        #expect(result == .correct)
    }

    // MARK: - Malformed payload

    @Test func malformedPayloadMultipleChoice() {
        let exercise = Exercise(key: "bad", orderIndex: 0, type: .multipleChoice)
        exercise.payloadData = Data([0x00, 0xFF])
        exercise.correctAnswerText = "fallback"
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .index(0), exercise: exercise)
        if case .incorrect(let canonical) = result {
            #expect(canonical == "fallback")
        } else {
            #expect(Bool(false), "Expected incorrect for malformed payload")
        }
    }

    @Test func missingPayloadMultipleChoice() {
        let exercise = Exercise(key: "nopayload", orderIndex: 0, type: .multipleChoice)
        exercise.correctAnswerText = "fallback"
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .index(0), exercise: exercise)
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect for missing payload")
        }
    }

    @Test func missingPayloadBuildSentence() {
        let exercise = Exercise(key: "nopayload", orderIndex: 0, type: .buildSentence)
        exercise.correctAnswerText = "fallback"
        let validator = ExerciseValidator()
        let result = validator.validate(answer: .wordOrder(["test"]), exercise: exercise)
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect for missing payload")
        }
    }

    // MARK: - Listening comprehension

    private func makeListeningExercise(
        options: [String] = ["Доброе утро!", "Добрый вечер!", "Привет!"],
        correctIndex: Int = 0,
        correctAnswer: String = "Доброе утро!"
    ) -> Exercise {
        let exercise = Exercise(key: "lc", orderIndex: 0, type: .listeningComprehension)
        exercise.correctAnswerText = correctAnswer
        exercise.acceptedAnswers = []
        exercise.payloadData = try? JSONEncoder().encode(
            ListeningComprehensionPayload(
                audioFileName: "gunaydin.mp3",
                transcript: "Günaydın!",
                options: options,
                correctIndex: correctIndex
            )
        )
        return exercise
    }

    @Test func listeningCorrectIndexAtZero() {
        let exercise = makeListeningExercise(correctIndex: 0)
        let result = ExerciseValidator().validate(answer: .index(0), exercise: exercise)
        #expect(result == .correct)
    }

    /// Guards the original defect: listening was validated through
    /// `MultipleChoiceValidator`, so a non-zero `correctIndex` could never be
    /// scored correct.
    @Test func listeningCorrectIndexNonZero() {
        let exercise = makeListeningExercise(correctIndex: 2, correctAnswer: "Привет!")
        let result = ExerciseValidator().validate(answer: .index(2), exercise: exercise)
        #expect(result == .correct)
    }

    @Test func listeningIncorrectIndexReportsCorrectOption() {
        let exercise = makeListeningExercise(correctIndex: 1, correctAnswer: "Добрый вечер!")
        let result = ExerciseValidator().validate(answer: .index(0), exercise: exercise)
        if case .incorrect(let canonical) = result {
            #expect(canonical == "Добрый вечер!")
        } else {
            #expect(Bool(false), "Expected incorrect")
        }
    }

    /// Regression guard for the original defect. A legacy listening payload
    /// (no `correctIndex`) cannot be decoded as a `MultipleChoicePayload`,
    /// which is exactly why routing listening through `MultipleChoiceValidator`
    /// marked every answer incorrect. `ListeningValidator` now owns this type
    /// and fails gracefully instead of silently mis-scoring.
    @Test func legacyListeningPayloadWithoutCorrectIndexIsNotMultipleChoice() throws {
        let legacyJSON = """
        {"audioFileName":"gunaydin.mp3","transcript":"Günaydın!","options":["Доброе утро!","Привет!"]}
        """
        let data = try #require(legacyJSON.data(using: .utf8))

        // Proves the two payload shapes are genuinely incompatible.
        #expect((try? JSONDecoder().decode(MultipleChoicePayload.self, from: data)) == nil)
        #expect((try? JSONDecoder().decode(ListeningComprehensionPayload.self, from: data)) == nil)

        let exercise = Exercise(key: "lc.legacy", orderIndex: 0, type: .listeningComprehension)
        exercise.payloadData = data
        exercise.correctAnswerText = "Доброе утро!"
        if case .incorrect = ExerciseValidator().validate(answer: .index(0), exercise: exercise) {
            // expected: undecodable payload degrades safely
        } else {
            #expect(Bool(false), "Expected incorrect for legacy payload")
        }
    }

    /// The router must dispatch listening to `ListeningValidator`, and that
    /// validator must agree with the router's result.
    @Test func listeningIsRoutedToListeningValidator() {
        let exercise = makeListeningExercise(correctIndex: 2, correctAnswer: "Привет!")
        let routed = ExerciseValidator().validate(answer: .index(2), exercise: exercise)
        let direct = ListeningValidator().validate(answer: .index(2), exercise: exercise)
        #expect(routed == .correct)
        #expect(routed == direct)
    }

    @Test func listeningWrongAnswerType() {
        let exercise = makeListeningExercise()
        let result = ExerciseValidator().validate(answer: .text("Доброе утро!"), exercise: exercise)
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect for text answer to listening")
        }
    }

    @Test func listeningOutOfBoundsCorrectIndexFallsBackToCorrectAnswerText() {
        let exercise = makeListeningExercise(correctIndex: 99, correctAnswer: "fallback")
        let result = ExerciseValidator().validate(answer: .index(0), exercise: exercise)
        if case .incorrect(let canonical) = result {
            #expect(canonical == "fallback")
        } else {
            #expect(Bool(false), "Expected incorrect")
        }
    }

    @Test func malformedPayloadListening() {
        let exercise = Exercise(key: "lc.bad", orderIndex: 0, type: .listeningComprehension)
        exercise.payloadData = Data([0x00, 0xFF])
        exercise.correctAnswerText = "fallback"
        let result = ExerciseValidator().validate(answer: .index(0), exercise: exercise)
        if case .incorrect(let canonical) = result {
            #expect(canonical == "fallback")
        } else {
            #expect(Bool(false), "Expected incorrect for malformed payload")
        }
    }

    @Test func missingPayloadListening() {
        let exercise = Exercise(key: "lc.nopayload", orderIndex: 0, type: .listeningComprehension)
        exercise.correctAnswerText = "fallback"
        let result = ExerciseValidator().validate(answer: .index(0), exercise: exercise)
        if case .incorrect = result {
            // expected
        } else {
            #expect(Bool(false), "Expected incorrect for missing payload")
        }
    }
}
