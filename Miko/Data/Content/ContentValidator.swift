import Foundation

/// Validates a `ContentBundle` for structural correctness before import.
///
/// Produces a list of validation errors. An empty list means the content is valid.
enum ContentValidator {

    static func validate(_ bundle: ContentBundle) -> [ContentError] {
        var errors: [ContentError] = []

        errors += validateCourse(bundle.course)
        errors += validateUniqueKeys(
            bundle.levels.map(\.key), label: "level"
        )
        errors += validateUniqueKeys(
            bundle.units.map(\.key), label: "unit"
        )
        errors += validateUniqueKeys(
            bundle.lessons.map(\.key), label: "lesson"
        )
        errors += validateUniqueKeys(
            bundle.vocabulary.map(\.key), label: "vocabulary"
        )
        errors += validateUniqueKeys(
            bundle.grammar.map(\.key), label: "grammar"
        )

        let exerciseKeys = bundle.lessons.flatMap { $0.exercises.map(\.key) }
        errors += validateUniqueKeys(exerciseKeys, label: "exercise")

        let levelKeys = Set(bundle.levels.map(\.key))
        let unitKeys = Set(bundle.units.map(\.key))
        let lessonKeys = Set(bundle.lessons.map(\.key))
        let vocabKeys = Set(bundle.vocabulary.map(\.key))
        let grammarKeys = Set(bundle.grammar.map(\.key))

        for level in bundle.levels {
            errors += validate("level \(level.key)", level.unitKeys.allSatisfy { unitKeys.contains($0) }) {
                level.unitKeys.compactMap { unitKeys.contains($0) ? nil : $0 }
                    .map { "level \(level.key) references unknown unit \($0)" }
            }
        }

        for unit in bundle.units {
            errors += validate("unit \(unit.key)", levelKeys.contains(unit.levelKey)) {
                if !levelKeys.contains(unit.levelKey) {
                    return ["unit \(unit.key) references unknown level \(unit.levelKey)"]
                }
                return []
            }
            errors += validate("unit \(unit.key)", unit.lessonKeys.allSatisfy { lessonKeys.contains($0) }) {
                unit.lessonKeys.compactMap { lessonKeys.contains($0) ? nil : $0 }
                    .map { "unit \(unit.key) references unknown lesson \($0)" }
            }
        }

        for lesson in bundle.lessons {
            errors += validate("lesson \(lesson.key)", unitKeys.contains(lesson.unitKey)) {
                if !unitKeys.contains(lesson.unitKey) {
                    return ["lesson \(lesson.key) references unknown unit \(lesson.unitKey)"]
                }
                return []
            }
            errors += validate("lesson \(lesson.key)", lesson.vocabularyKeys.allSatisfy { vocabKeys.contains($0) }) {
                lesson.vocabularyKeys.compactMap { vocabKeys.contains($0) ? nil : $0 }
                    .map { "lesson \(lesson.key) references unknown vocabulary \($0)" }
            }
            errors += validate("lesson \(lesson.key)", lesson.grammarKeys.allSatisfy { grammarKeys.contains($0) }) {
                lesson.grammarKeys.compactMap { grammarKeys.contains($0) ? nil : $0 }
                    .map { "lesson \(lesson.key) references unknown grammar \($0)" }
            }
            errors += validate("lesson \(lesson.key)", !lesson.exercises.isEmpty) {
                return ["lesson \(lesson.key) has no exercises"]
            }

            let exerciseOrderIndices = lesson.exercises.map(\.orderIndex)
            if !areUnique(exerciseOrderIndices) {
                errors.append(.validation("lesson \(lesson.key) has duplicate exercise orderIndices"))
            }

            for exercise in lesson.exercises {
                if exercise.orderIndex < 0 {
                    errors.append(.validation("exercise \(exercise.key) has negative orderIndex"))
                }
                errors += validate("exercise \(exercise.key)", exercise.vocabularyKeys.allSatisfy { vocabKeys.contains($0) }) {
                    exercise.vocabularyKeys.compactMap { vocabKeys.contains($0) ? nil : $0 }
                        .map { "exercise \(exercise.key) references unknown vocabulary \($0)" }
                }
                errors += validateExercisePayload(exercise)
            }
        }

        for vocab in bundle.vocabulary {
            if vocab.sourceText.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append(.validation("vocabulary \(vocab.key) has empty sourceText"))
            }
            if vocab.targetText.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append(.validation("vocabulary \(vocab.key) has empty targetText"))
            }
        }

        for grammar in bundle.grammar {
            if grammar.titleKey.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append(.validation("grammar \(grammar.key) has empty titleKey"))
            }
        }

        return errors
    }

    private static func validateCourse(_ course: CourseContentDTO) -> [ContentError] {
        var errors: [ContentError] = []
        let source = course.sourceLanguageCode.trimmingCharacters(in: .whitespaces)
        let target = course.targetLanguageCode.trimmingCharacters(in: .whitespaces)
        if source.isEmpty {
            errors.append(.validation("course \(course.key) has empty sourceLanguageCode"))
        }
        if target.isEmpty {
            errors.append(.validation("course \(course.key) has empty targetLanguageCode"))
        }
        if !source.isEmpty, !target.isEmpty, source == target {
            errors.append(.validation("course \(course.key) source and target languages are identical"))
        }
        if course.key.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.validation("course has empty key"))
        }
        return errors
    }

    private static func validateExercisePayload(_ exercise: ExerciseContentDTO) -> [ContentError] {
        let answerRequired = setOf(
            ExerciseType.translateWord,
            ExerciseType.translateSentence,
            ExerciseType.fillBlank,
            ExerciseType.buildSentence,
            ExerciseType.multipleChoice
        )

        if answerRequired.contains(exercise.type) {
            if exercise.correctAnswerText.trimmingCharacters(in: .whitespaces).isEmpty {
                return [.validation("exercise \(exercise.key) of type \(exercise.type.rawValue) has empty correctAnswerText")]
            }
        }

        let payloadRequired = setOf(
            ExerciseType.multipleChoice,
            ExerciseType.buildSentence,
            ExerciseType.matchPairs,
            ExerciseType.fillBlank,
            ExerciseType.listeningComprehension
        )

        if payloadRequired.contains(exercise.type) {
            guard let payload = exercise.payload else {
                return [.validation("exercise \(exercise.key) of type \(exercise.type.rawValue) has missing payload")]
            }
            return validatePayload(payload, type: exercise.type, key: exercise.key)
        }

        return []
    }

    private static func validatePayload(
        _ json: JSONValue,
        type: ExerciseType,
        key: String
    ) -> [ContentError] {
        guard let data = try? JSONEncoder().encode(json) else {
            return [.validation("exercise \(key) failed to encode payload")]
        }
        let decoder = JSONDecoder()

        switch type {
        case .multipleChoice:
            guard let p = try? decoder.decode(MultipleChoicePayload.self, from: data) else {
                return [.validation("exercise \(key) has invalid multipleChoice payload")]
            }
            if p.options.isEmpty || p.correctIndex < 0 || p.correctIndex >= p.options.count {
                return [.validation("exercise \(key) multipleChoice payload has invalid options/correctIndex")]
            }
        case .buildSentence:
            guard let p = try? decoder.decode(BuildSentencePayload.self, from: data) else {
                return [.validation("exercise \(key) has invalid buildSentence payload")]
            }
            let wordSet = Set(p.wordBank)
            if !p.sentenceWords.allSatisfy({ wordSet.contains($0) }) {
                return [.validation("exercise \(key) buildSentence sentenceWords not all in wordBank")]
            }
        case .matchPairs:
            guard let p = try? decoder.decode(MatchPairsPayload.self, from: data) else {
                return [.validation("exercise \(key) has invalid matchPairs payload")]
            }
            if p.pairs.isEmpty {
                return [.validation("exercise \(key) matchPairs has empty pairs")]
            }
        case .fillBlank:
            guard let p = try? decoder.decode(FillBlankPayload.self, from: data) else {
                return [.validation("exercise \(key) has invalid fillBlank payload")]
            }
            if p.options.isEmpty || p.blank.trimmingCharacters(in: .whitespaces).isEmpty {
                return [.validation("exercise \(key) fillBlank has empty options or blank")]
            }
            // Strict: seeds must use the canonical placeholder so every
            // fillBlank template renders a blank slot. Rendering is tolerant
            // of other underscore runs, but authored content must be exact.
            if !p.template.contains(FillBlankPayload.canonicalPlaceholder) {
                return [.validation("exercise \(key) fillBlank template is missing the '\(FillBlankPayload.canonicalPlaceholder)' placeholder")]
            }
            // The answer must be selectable.
            if !p.options.contains(p.blank) {
                return [.validation("exercise \(key) fillBlank blank '\(p.blank)' is not present in options")]
            }
        case .listeningComprehension:
            guard let p = try? decoder.decode(ListeningComprehensionPayload.self, from: data) else {
                return [.validation("exercise \(key) has invalid listeningComprehension payload")]
            }
            if p.options.isEmpty || p.audioFileName.trimmingCharacters(in: .whitespaces).isEmpty {
                return [.validation("exercise \(key) listeningComprehension has empty options or audioFileName")]
            }
            // Every seeded listening exercise must be answerable: an out-of-
            // bounds correctIndex makes the correct option unreachable.
            if p.correctIndex < 0 || p.correctIndex >= p.options.count {
                return [.validation("exercise \(key) listeningComprehension payload has invalid correctIndex")]
            }
        default:
            break
        }
        return []
    }

    // MARK: - Helpers

    private static func validateUniqueKeys(_ keys: [String], label: String) -> [ContentError] {
        if !areUnique(keys) {
            let duplicates = Dictionary(grouping: keys, by: { $0 })
                .filter { $0.value.count > 1 }.keys
            return [.validation("Duplicate \(label) key(s): \(duplicates.sorted().joined(separator: ", "))")]
        }
        let empty = keys.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !empty.isEmpty {
            return [.validation("\(label) contains empty key(s)")]
        }
        return []
    }

    private static func validate(
        _ context: String,
        _ condition: @autoclosure () -> Bool,
        _ errors: () -> [String]
    ) -> [ContentError] {
        if !condition() {
            return errors().map { ContentError.validation($0) }
        }
        return []
    }

    private static func areUnique(_ values: [some Hashable]) -> Bool {
        Set(values).count == values.count
    }

    /// A set of unique values without a dependency on Foundation's `Set`.
    private static func setOf(_ items: ExerciseType...) -> Set<ExerciseType> {
        Set(items)
    }
}