import Foundation
import SwiftData
import Testing
@testable import Miko

/// Scans the entire bundled content dataset for integrity problems.
///
/// Detects duplicate keys, broken references, missing required fields,
/// invalid exercise types, invalid CEFR values, and invalid order indices.
@Suite(.serialized)
struct ContentIntegrityTests {

    @Test func noDuplicateKeysAcrossAllEntities() throws {
        let bundle = try ContentTestSupport.loadBundle()

        let levelKeys = bundle.levels.map(\.key)
        let unitKeys = bundle.units.map(\.key)
        let lessonKeys = bundle.lessons.map(\.key)
        let exerciseKeys = bundle.lessons.flatMap { $0.exercises.map(\.key) }
        let vocabKeys = bundle.vocabulary.map(\.key)
        let grammarKeys = bundle.grammar.map(\.key)

        #expect(Set(levelKeys).count == levelKeys.count)
        #expect(Set(unitKeys).count == unitKeys.count)
        #expect(Set(lessonKeys).count == lessonKeys.count)
        #expect(Set(exerciseKeys).count == exerciseKeys.count)
        #expect(Set(vocabKeys).count == vocabKeys.count)
        #expect(Set(grammarKeys).count == grammarKeys.count)
    }

    @Test func allReferencesResolve() throws {
        let bundle = try ContentTestSupport.loadBundle()

        let unitKeys = Set(bundle.units.map(\.key))
        let lessonKeys = Set(bundle.lessons.map(\.key))
        let vocabKeys = Set(bundle.vocabulary.map(\.key))
        let grammarKeys = Set(bundle.grammar.map(\.key))

        for level in bundle.levels {
            for unitKey in level.unitKeys {
                #expect(unitKeys.contains(unitKey), "level \(level.key) → missing unit \(unitKey)")
            }
        }
        for unit in bundle.units {
            #expect(bundle.levels.map(\.key).contains(unit.levelKey), "unit \(unit.key) → missing level \(unit.levelKey)")
            for lessonKey in unit.lessonKeys {
                #expect(lessonKeys.contains(lessonKey), "unit \(unit.key) → missing lesson \(lessonKey)")
            }
        }
        for lesson in bundle.lessons {
            #expect(unitKeys.contains(lesson.unitKey), "lesson \(lesson.key) → missing unit \(lesson.unitKey)")
            for v in lesson.vocabularyKeys {
                #expect(vocabKeys.contains(v), "lesson \(lesson.key) → missing vocab \(v)")
            }
            for g in lesson.grammarKeys {
                #expect(grammarKeys.contains(g), "lesson \(lesson.key) → missing grammar \(g)")
            }
            for ex in lesson.exercises {
                for v in ex.vocabularyKeys {
                    #expect(vocabKeys.contains(v), "exercise \(ex.key) → missing vocab \(v)")
                }
            }
        }
    }

    @Test func orderIndicesAreValidAndSequential() throws {
        let bundle = try ContentTestSupport.loadBundle()

        for lesson in bundle.lessons {
            let indices = lesson.exercises.map(\.orderIndex)
            #expect(Set(indices).count == indices.count, "lesson \(lesson.key) has duplicate order indices")
            #expect(indices.allSatisfy { $0 >= 0 })
            #expect(indices.sorted() == Array(0..<indices.count), "lesson \(lesson.key) order indices not sequential")
        }
    }

    @Test func ceFrLevelsAreValid() throws {
        let bundle = try ContentTestSupport.loadBundle()
        for level in bundle.levels {
            #expect(CEFRLevel.allCases.contains(level.cefr))
        }
        for vocab in bundle.vocabulary {
            #expect(CEFRLevel.allCases.contains(vocab.cefr))
        }
        for grammar in bundle.grammar {
            #expect(CEFRLevel.allCases.contains(grammar.cefr))
        }
    }

    @Test func validatorReportsNoErrorsOnBundledContent() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let errors = ContentValidator.validate(bundle)
        #expect(errors.isEmpty, "Bundled content is invalid: \(errors.map(\.errorDescription))")
    }

    @Test func vocabularyKeysReferencedByLessonsExist() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let vocabKeys = Set(bundle.vocabulary.map(\.key))
        let referenced = Set(bundle.lessons.flatMap(\.vocabularyKeys))
        #expect(referenced.isSubset(of: vocabKeys))
    }

    @Test func originLessonUsesBelarus() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let vocabulary = try #require(
            bundle.vocabulary.first(where: { $0.key == "vocab.belarusluyum" })
        )
        let lesson = try #require(bundle.lessons.first(where: { $0.key == "a1.u2.l2" }))

        #expect(vocabulary.sourceText == "Я из Беларуси")
        #expect(vocabulary.targetText == "Belarusluyum")
        #expect(lesson.vocabularyKeys.contains(vocabulary.key))
        #expect(!lesson.vocabularyKeys.contains("vocab.russiyaliyim"))
    }

    @Test func cityLessonsConnectBelarusAndTurkiye() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let cityLesson = try #require(bundle.lessons.first(where: { $0.key == "a1.u6.l1" }))
        let travelLesson = try #require(bundle.lessons.first(where: { $0.key == "a1.u6.l2" }))

        let cityText = cityLesson.exercises
            .flatMap { [$0.promptText, $0.correctAnswerText] }
            .joined(separator: " ")
        let travelText = travelLesson.exercises
            .flatMap { [$0.promptText, $0.correctAnswerText] }
            .joined(separator: " ")

        #expect(cityText.contains("Минск"))
        #expect(cityText.contains("Стамбул"))
        #expect(cityText.contains("Беларус"))
        #expect(cityText.contains("Турц"))
        #expect(travelText.contains("Беларус"))
        #expect(travelText.contains("Турц"))
        #expect(travelText.contains("Minsk'ten İstanbul'a"))
    }

    // MARK: - Fill blank templates (HIGH-5)

    /// Every seeded fillBlank template must carry the canonical placeholder,
    /// be splittable by the renderer, and offer its answer among the options.
    @Test func allSeededFillBlankTemplatesAreValid() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let fillBlanks = bundle.lessons
            .flatMap(\.exercises)
            .filter { $0.type == .fillBlank }

        #expect(!fillBlanks.isEmpty, "Expected seeded fillBlank exercises")

        for exercise in fillBlanks {
            let payloadValue = try #require(exercise.payload, "fillBlank \(exercise.key) has no payload")
            let data = try JSONEncoder().encode(payloadValue)
            let payload = try JSONDecoder().decode(FillBlankPayload.self, from: data)

            #expect(
                payload.template.contains(FillBlankPayload.canonicalPlaceholder),
                "fillBlank \(exercise.key) template lacks the canonical placeholder: \(payload.template)"
            )
            #expect(
                FillBlankPayload.split(template: payload.template) != nil,
                "fillBlank \(exercise.key) template is not splittable: \(payload.template)"
            )
            #expect(
                payload.options.contains(payload.blank),
                "fillBlank \(exercise.key) blank is not among its options"
            )
        }
    }

    /// A few previously corrupted A2 prompts were structurally valid JSON
    /// yet formed impossible or ungrammatical sentences in the actual UI.
    @Test func correctedA2FillBlanksHaveAnswerableSentences() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let exercises = Dictionary(uniqueKeysWithValues: bundle.lessons
            .flatMap(\.exercises)
            .map { ($0.key, $0) })

        for (key, expectedTemplate, expectedBlank) in [
            ("a2.u1.l1.e4", "Ablamın iki ____ var.", "çocuğu"),
            ("a2.u2.l2.e3", "Sabah yediden ____ kalkıyorum.", "önce"),
            ("a2.u7.l2.e4", "Yazın ____ gidiyoruz.", "tatile")
        ] {
            let exercise = try #require(exercises[key])
            let payloadValue = try #require(exercise.payload)
            let data = try JSONEncoder().encode(payloadValue)
            let payload = try JSONDecoder().decode(FillBlankPayload.self, from: data)
            #expect(payload.template == expectedTemplate, "Unexpected template in \(key)")
            #expect(payload.blank == expectedBlank, "Unexpected blank in \(key)")
            #expect(exercise.correctAnswerText == expectedBlank, "Wrong answer in \(key)")
        }
    }

    @Test func a2FamilySentencePromptMatchesIntensifier() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let lesson = try #require(bundle.lessons.first { $0.key == "a2.u1.l1" })
        let exercise = try #require(lesson.exercises.first { $0.key == "a2.u1.l1.e6" })

        #expect(exercise.promptText.contains("очень маленький"))
        #expect(exercise.correctAnswerText == "Oğlum çok küçük.")
    }

    @Test func turkishTranslationAnswersCannotBeCyrillic() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let turkishWords = bundle.lessons.flatMap(\.exercises)
            .filter { $0.type == .translateWord }
        for exercise in turkishWords {
            for answer in [exercise.correctAnswerText] + exercise.acceptedAnswers {
                #expect(!answer.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) },
                        "Turkish answer in \(exercise.key) uses Cyrillic: \(answer)")
            }
        }
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        try ContentImporter.import(bundle, into: context)
        let imported = try context.fetch(FetchDescriptor<Exercise>())
        let sport = try #require(imported.first { $0.key == "a2.u4.l2.e2" })
        let reading = try #require(imported.first { $0.key == "a2.u7.l1.e2" })
        #expect(ExerciseValidator().validate(answer: .text("спорт"), exercise: sport) != .correct)
        #expect(ExerciseValidator().validate(answer: .text("Окумак"), exercise: reading) != .correct)
    }

    @Test func doctorAppointmentPromptAndSyrupSpellingAgreeWithAnswers() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let lesson = try #require(bundle.lessons.first { $0.key == "a2.u6.l2" })
        let appointment = try #require(lesson.exercises.first { $0.key == "a2.u6.l2.e4" })
        let prescription = try #require(lesson.exercises.first { $0.key == "a2.u6.l2.e3" })
        let syrup = try #require(bundle.vocabulary.first { $0.key == "vocab.surup" })
        let data = try #require(appointment.payload)
        let payload = try JSONDecoder().decode(
            MultipleChoicePayload.self,
            from: JSONEncoder().encode(data)
        )

        #expect(appointment.promptText.contains("при записи на приём"))
        #expect(appointment.correctAnswerText == "Randevu alırken")
        #expect(payload.options[payload.correctIndex] == appointment.correctAnswerText)
        #expect(payload.options.contains("Şurup içerken"))
        #expect(syrup.targetText == "Şurup")
        let fillPayload = try JSONDecoder().decode(
            FillBlankPayload.self,
            from: JSONEncoder().encode(try #require(prescription.payload))
        )
        #expect(fillPayload.options.contains("şurup"))
        #expect(!fillPayload.options.contains("surup"))
    }

    @Test func finalVacationSentencePromptDescribesRequiredAnswer() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let lesson = try #require(bundle.lessons.first { $0.key == "a2.u7.l2" })
        let exercise = try #require(lesson.exercises.first { $0.key == "a2.u7.l2.e6" })
        #expect(exercise.promptText == "Соберите предложение: «Я фотографирую на пляже.»")
        #expect(exercise.correctAnswerText == "Plajda fotoğraf çekiyorum.")
    }

    // MARK: - Listening comprehension (CRITICAL-1)

    /// Every seeded listening exercise must declare an in-bounds
    /// `correctIndex`. Without it the payload cannot be decoded and the
    /// exercise becomes unanswerable.
    @Test func allSeededListeningExercisesHaveInBoundsCorrectIndex() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let listening = bundle.lessons
            .flatMap(\.exercises)
            .filter { $0.type == .listeningComprehension }

        #expect(!listening.isEmpty, "Expected seeded listening exercises")

        for exercise in listening {
            let payloadValue = try #require(exercise.payload, "listening \(exercise.key) has no payload")
            let data = try JSONEncoder().encode(payloadValue)
            let payload = try #require(
                try? JSONDecoder().decode(ListeningComprehensionPayload.self, from: data),
                "listening \(exercise.key) payload does not decode as ListeningComprehensionPayload"
            )
            #expect(payload.correctIndex >= 0, "listening \(exercise.key) has negative correctIndex")
            #expect(
                payload.correctIndex < payload.options.count,
                "listening \(exercise.key) correctIndex out of bounds"
            )
            #expect(!payload.transcript.trimmingCharacters(in: .whitespaces).isEmpty,
                    "listening \(exercise.key) has empty transcript")
        }
    }

    /// End-to-end guard: seed → decoding → validation → runtime answerability.
    ///
    /// Imports the real bundled content into a container, then drives every
    /// seeded listening exercise through the production `ExerciseValidator`
    /// using the payload's own `correctIndex`. Selecting that option MUST be
    /// scored correct, and every other option MUST be scored incorrect.
    @Test func seededListeningExercisesAreAnswerableThroughValidator() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let bundle = try ContentTestSupport.loadBundle()
        try ContentImporter.import(bundle, into: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
            .filter { $0.type == .listeningComprehension }
        #expect(!exercises.isEmpty, "Expected imported listening exercises")

        let validator = ExerciseValidator()
        for exercise in exercises {
            let data = try #require(exercise.payloadData, "listening \(exercise.key) lost its payload on import")
            let payload = try #require(
                try? JSONDecoder().decode(ListeningComprehensionPayload.self, from: data),
                "listening \(exercise.key) payload does not decode after import"
            )

            // The seeded correct option must be answerable.
            #expect(
                validator.validate(answer: .index(payload.correctIndex), exercise: exercise) == .correct,
                "listening \(exercise.key) is not answerable at its own correctIndex"
            )

            // Every other option must be scored incorrect.
            for index in payload.options.indices where index != payload.correctIndex {
                if case .incorrect = validator.validate(answer: .index(index), exercise: exercise) {
                    // expected
                } else {
                    #expect(Bool(false), "listening \(exercise.key) accepted wrong option \(index)")
                }
            }

            // The declared correct option should agree with correctAnswerText.
            #expect(
                payload.options[payload.correctIndex] == exercise.correctAnswerText,
                "listening \(exercise.key) correctIndex option disagrees with correctAnswerText"
            )
        }
    }

    /// Seed → SwiftData import → the same validator used by the exercise UI.
    /// This is a mechanical answerability check, not a substitute for tapping
    /// the actual views or reviewing the linguistic correctness of answers.
    @Test func allSeededExerciseCanonicalAnswersValidate() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        try ContentImporter.import(ContentTestSupport.loadBundle(), into: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.count == 217)

        let validator = ExerciseValidator()
        for exercise in exercises {
            let answer: ExerciseAnswer
            switch exercise.type {
            case .multipleChoice:
                let data = try #require(exercise.payloadData)
                let payload = try JSONDecoder().decode(MultipleChoicePayload.self, from: data)
                try #require(payload.options.indices.contains(payload.correctIndex))
                answer = .index(payload.correctIndex)
                #expect(payload.options[payload.correctIndex] == exercise.correctAnswerText)
            case .listeningComprehension:
                let data = try #require(exercise.payloadData)
                let payload = try JSONDecoder().decode(ListeningComprehensionPayload.self, from: data)
                answer = .index(payload.correctIndex)
            case .buildSentence:
                let data = try #require(exercise.payloadData)
                let payload = try JSONDecoder().decode(BuildSentencePayload.self, from: data)
                answer = .wordOrder(payload.sentenceWords)
                #expect(payload.sentenceWords.joined(separator: " ") == exercise.correctAnswerText)
                for word in payload.sentenceWords {
                    #expect(payload.wordBank.contains(word), "Missing token in \(exercise.key): \(word)")
                }
            case .matchPairs:
                let data = try #require(exercise.payloadData)
                let payload = try JSONDecoder().decode(MatchPairsPayload.self, from: data)
                answer = .matchedPairs(payload.pairs.map { ($0.source, $0.target) })
            case .fillBlank:
                let data = try #require(exercise.payloadData)
                let payload = try JSONDecoder().decode(FillBlankPayload.self, from: data)
                answer = .text(payload.blank)
            case .translateWord, .translateSentence, .pronunciation:
                answer = .text(exercise.correctAnswerText)
            case .vocabularyReview:
                answer = .acknowledged
            }
            #expect(validator.validate(answer: answer, exercise: exercise) == .correct,
                    "Unanswerable seeded exercise: \(exercise.key)")
        }
    }
}
