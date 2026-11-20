import Testing
@testable import Miko

@Suite(.serialized)
struct ContentValidatorTests {

    @Test func validBundlePasses() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let errors = ContentValidator.validate(bundle)
        #expect(errors.isEmpty, "Expected no errors, got: \(errors.map(\.errorDescription))")
    }

    @Test func rejectsDuplicateVocabularyKey() {
        let bundle = ContentBundle(
            course: CourseContentDTO(key: "c", sourceLanguageCode: "ru", targetLanguageCode: "tr", version: 1, titleKey: "t"),
            levels: [],
            units: [],
            lessons: [],
            vocabulary: [
                VocabularyContentDTO(key: "vocab.x", sourceText: "а", targetText: "a", pronunciation: "", partOfSpeech: .noun, cefr: .a1, exampleSource: "", exampleTarget: "", difficulty: 1, imageAsset: nil, audioFileName: nil),
                VocabularyContentDTO(key: "vocab.x", sourceText: "б", targetText: "b", pronunciation: "", partOfSpeech: .noun, cefr: .a1, exampleSource: "", exampleTarget: "", difficulty: 1, imageAsset: nil, audioFileName: nil)
            ],
            grammar: []
        )
        let errors = ContentValidator.validate(bundle)
        #expect(errors.contains { $0.errorDescription?.contains("Duplicate vocabulary") == true })
    }

    @Test func rejectsUnknownUnitReference() {
        let lesson = LessonContentDTO(
            key: "a1.u1.l1",
            orderIndex: 0,
            titleKey: "t",
            kind: .skill,
            unitKey: "a1.unknown",
            vocabularyKeys: [],
            grammarKeys: [],
            exercises: [
                ExerciseContentDTO(key: "e1", type: .translateWord, orderIndex: 0, promptText: "p", promptKey: "", hintKey: "", correctAnswerText: "x", acceptedAnswers: [], vocabularyKeys: [], payload: nil)
            ]
        )
        let bundle = ContentBundle(
            course: CourseContentDTO(key: "c", sourceLanguageCode: "ru", targetLanguageCode: "tr", version: 1, titleKey: "t"),
            levels: [],
            units: [],
            lessons: [lesson],
            vocabulary: [],
            grammar: []
        )
        let errors = ContentValidator.validate(bundle)
        #expect(errors.contains { $0.errorDescription?.contains("unknown unit") == true })
    }

    @Test func rejectsEmptyCourseLanguage() {
        let bundle = ContentBundle(
            course: CourseContentDTO(key: "c", sourceLanguageCode: "", targetLanguageCode: "tr", version: 1, titleKey: "t"),
            levels: [], units: [], lessons: [], vocabulary: [], grammar: []
        )
        let errors = ContentValidator.validate(bundle)
        #expect(errors.contains { $0.errorDescription?.contains("sourceLanguageCode") == true })
    }

    @Test func rejectsExerciseMissingAnswer() {
        let lesson = LessonContentDTO(
            key: "l1", orderIndex: 0, titleKey: "t", kind: .skill, unitKey: "u1",
            vocabularyKeys: [], grammarKeys: [],
            exercises: [
                ExerciseContentDTO(key: "e1", type: .translateWord, orderIndex: 0, promptText: "p", promptKey: "", hintKey: "", correctAnswerText: "", acceptedAnswers: [], vocabularyKeys: [], payload: nil)
            ]
        )
        let bundle = ContentBundle(
            course: CourseContentDTO(key: "c", sourceLanguageCode: "ru", targetLanguageCode: "tr", version: 1, titleKey: "t"),
            levels: [], units: [UnitContentDTO(key: "u1", orderIndex: 0, titleKey: "t", theme: "", summaryKey: "", levelKey: "", lessonKeys: ["l1"])],
            lessons: [lesson], vocabulary: [], grammar: []
        )
        let errors = ContentValidator.validate(bundle)
        #expect(errors.contains { $0.errorDescription?.contains("correctAnswerText") == true })
    }

    @Test func rejectsInvalidMultipleChoicePayload() {
        let lesson = LessonContentDTO(
            key: "l1", orderIndex: 0, titleKey: "t", kind: .skill, unitKey: "u1",
            vocabularyKeys: [], grammarKeys: [],
            exercises: [
                ExerciseContentDTO(key: "e1", type: .multipleChoice, orderIndex: 0, promptText: "p", promptKey: "", hintKey: "", correctAnswerText: "x", acceptedAnswers: [], vocabularyKeys: [], payload: .object(["options": .array([.string("a")]), "correctIndex": .number(5)]))
            ]
        )
        let bundle = ContentBundle(
            course: CourseContentDTO(key: "c", sourceLanguageCode: "ru", targetLanguageCode: "tr", version: 1, titleKey: "t"),
            levels: [], units: [UnitContentDTO(key: "u1", orderIndex: 0, titleKey: "t", theme: "", summaryKey: "", levelKey: "", lessonKeys: ["l1"])],
            lessons: [lesson], vocabulary: [], grammar: []
        )
        let errors = ContentValidator.validate(bundle)
        #expect(errors.contains { $0.errorDescription?.contains("multipleChoice") == true })
    }

    // MARK: - Listening comprehension payload

    /// Builds a single-exercise bundle around a listening payload.
    private func makeListeningBundle(payload: JSONValue?) -> ContentBundle {
        let lesson = LessonContentDTO(
            key: "l1", orderIndex: 0, titleKey: "t", kind: .skill, unitKey: "u1",
            vocabularyKeys: [], grammarKeys: [],
            exercises: [
                ExerciseContentDTO(key: "e1", type: .listeningComprehension, orderIndex: 0, promptText: "p", promptKey: "", hintKey: "", correctAnswerText: "x", acceptedAnswers: [], vocabularyKeys: [], payload: payload)
            ]
        )
        return ContentBundle(
            course: CourseContentDTO(key: "c", sourceLanguageCode: "ru", targetLanguageCode: "tr", version: 1, titleKey: "t"),
            levels: [], units: [UnitContentDTO(key: "u1", orderIndex: 0, titleKey: "t", theme: "", summaryKey: "", levelKey: "", lessonKeys: ["l1"])],
            lessons: [lesson], vocabulary: [], grammar: []
        )
    }

    private func listeningPayload(
        options: [String] = ["a", "b"],
        correctIndex: Double? = 0,
        audioFileName: String = "a.mp3"
    ) -> JSONValue {
        var dict: [String: JSONValue] = [
            "audioFileName": .string(audioFileName),
            "transcript": .string("Günaydın!"),
            "options": .array(options.map { .string($0) })
        ]
        if let correctIndex {
            dict["correctIndex"] = .number(correctIndex)
        }
        return .object(dict)
    }

    @Test func acceptsValidListeningPayload() {
        let errors = ContentValidator.validate(makeListeningBundle(payload: listeningPayload(correctIndex: 1)))
        // The skeleton bundle intentionally omits levels, so filter to the
        // payload errors this test is about.
        let listeningErrors = errors.filter {
            $0.errorDescription?.contains("listeningComprehension") == true
                || $0.errorDescription?.contains("correctIndex") == true
        }
        #expect(listeningErrors.isEmpty, "Expected no listening errors, got: \(listeningErrors.map(\.errorDescription))")
    }

    @Test func rejectsListeningPayloadMissingCorrectIndex() {
        let errors = ContentValidator.validate(makeListeningBundle(payload: listeningPayload(correctIndex: nil)))
        #expect(errors.contains { $0.errorDescription?.contains("listeningComprehension") == true })
    }

    @Test func rejectsListeningPayloadWithOutOfBoundsCorrectIndex() {
        let errors = ContentValidator.validate(makeListeningBundle(payload: listeningPayload(options: ["a", "b"], correctIndex: 5)))
        #expect(errors.contains { $0.errorDescription?.contains("correctIndex") == true })
    }

    @Test func rejectsListeningPayloadWithNegativeCorrectIndex() {
        let errors = ContentValidator.validate(makeListeningBundle(payload: listeningPayload(correctIndex: -1)))
        #expect(errors.contains { $0.errorDescription?.contains("correctIndex") == true })
    }

    @Test func rejectsListeningPayloadWithEmptyOptions() {
        let errors = ContentValidator.validate(makeListeningBundle(payload: listeningPayload(options: [], correctIndex: 0)))
        #expect(errors.contains { $0.errorDescription?.contains("listeningComprehension") == true })
    }

    @Test func rejectsListeningPayloadWithEmptyAudioFileName() {
        let errors = ContentValidator.validate(makeListeningBundle(payload: listeningPayload(audioFileName: "  ")))
        #expect(errors.contains { $0.errorDescription?.contains("audioFileName") == true })
    }

    @Test func rejectsListeningExerciseWithMissingPayload() {
        let errors = ContentValidator.validate(makeListeningBundle(payload: nil))
        #expect(errors.contains { $0.errorDescription?.contains("missing payload") == true })
    }

    // MARK: - FillBlank template validation (HIGH-5)

    private func makeFillBlankBundle(
        template: String,
        blank: String = "ekmek",
        options: [String] = ["ekmek", "çorba"]
    ) -> ContentBundle {
        let payload: JSONValue = .object([
            "template": .string(template),
            "blank": .string(blank),
            "options": .array(options.map { .string($0) })
        ])
        let lesson = LessonContentDTO(
            key: "l1", orderIndex: 0, titleKey: "t", kind: .skill, unitKey: "u1",
            vocabularyKeys: [], grammarKeys: [],
            exercises: [
                ExerciseContentDTO(key: "e1", type: .fillBlank, orderIndex: 0, promptText: "p", promptKey: "", hintKey: "", correctAnswerText: blank, acceptedAnswers: [], vocabularyKeys: [], payload: payload)
            ]
        )
        return ContentBundle(
            course: CourseContentDTO(key: "c", sourceLanguageCode: "ru", targetLanguageCode: "tr", version: 1, titleKey: "t"),
            levels: [], units: [UnitContentDTO(key: "u1", orderIndex: 0, titleKey: "t", theme: "", summaryKey: "", levelKey: "", lessonKeys: ["l1"])],
            lessons: [lesson], vocabulary: [], grammar: []
        )
    }

    private func fillBlankErrors(_ bundle: ContentBundle) -> [ContentError] {
        ContentValidator.validate(bundle).filter {
            $0.errorDescription?.contains("fillBlank") == true
        }
    }

    @Test func acceptsFillBlankWithCanonicalPlaceholder() {
        let errors = fillBlankErrors(makeFillBlankBundle(template: "Taze ____, lütfen."))
        #expect(errors.isEmpty, "Expected no fillBlank errors, got: \(errors.map(\.errorDescription))")
    }

    /// Strict validation: authored seeds must use the canonical placeholder,
    /// even though rendering tolerates 3+ underscores.
    @Test func rejectsFillBlankWithThreeUnderscorePlaceholder() {
        let errors = fillBlankErrors(makeFillBlankBundle(template: "___ dakika, lütfen."))
        #expect(errors.contains { $0.errorDescription?.contains("placeholder") == true })
    }

    @Test func rejectsFillBlankWithoutPlaceholder() {
        let errors = fillBlankErrors(makeFillBlankBundle(template: "Taze ekmek, lütfen."))
        #expect(errors.contains { $0.errorDescription?.contains("placeholder") == true })
    }

    @Test func rejectsFillBlankWhoseBlankIsNotAnOption() {
        let errors = fillBlankErrors(
            makeFillBlankBundle(template: "Taze ____.", blank: "ekmek", options: ["çorba", "kebap"])
        )
        #expect(errors.contains { $0.errorDescription?.contains("not present in options") == true })
    }

    @Test func rejectsFillBlankWithEmptyOptions() {
        let errors = fillBlankErrors(
            makeFillBlankBundle(template: "Taze ____.", blank: "ekmek", options: [])
        )
        #expect(errors.contains { $0.errorDescription?.contains("empty options") == true })
    }
}