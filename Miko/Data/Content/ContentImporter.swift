import Foundation
import SwiftData

/// Imports a validated `ContentBundle` into SwiftData.
///
/// Idempotent — entities are found or created by stable key, and existing
/// entities are updated with the latest content.
///
/// Performance: existing entities are pre-fetched once into dictionaries
/// keyed by stable content key, so each upsert is O(1) instead of O(N).
enum ContentImporter {

    static func `import`(_ bundle: ContentBundle, into context: ModelContext) throws {
        let errors = ContentValidator.validate(bundle)
        if !errors.isEmpty {
            throw ContentError.validation(
                "Content validation failed:\n" + errors.map(\.errorDescription).compactMap { $0 }.joined(separator: "\n")
            )
        }

        let courses = try prefetch(Course.self, context: context)
        let levels = try prefetch(Level.self, context: context)
        let units = try prefetch(Unit.self, context: context)
        let lessons = try prefetch(Lesson.self, context: context)
        let exercises = try prefetch(Exercise.self, context: context)
        let vocab = try prefetch(VocabularyItem.self, context: context)
        let grammar = try prefetch(GrammarTopic.self, context: context)
        let languages = try prefetchLanguages(context: context)

        let sourceLang = findOrCreateLanguage(
            code: bundle.course.sourceLanguageCode,
            languages: languages,
            context: context
        )
        let targetLang = findOrCreateLanguage(
            code: bundle.course.targetLanguageCode,
            languages: languages,
            context: context
        )

        let course = try upsertCourse(
            dto: bundle.course,
            source: sourceLang,
            target: targetLang,
            existing: courses,
            context: context
        )

        let grammarMap = try upsertGrammar(bundle.grammar, existing: grammar, context: context)
        let vocabMap = try upsertVocabulary(bundle.vocabulary, existing: vocab, context: context)
        let levelMap = try upsertLevels(bundle.levels, course: course, existing: levels, context: context)
        let unitMap = try upsertUnits(bundle.units, levels: levelMap, existing: units, context: context)
        let lessonMap = try upsertLessons(
            bundle.lessons,
            units: unitMap,
            vocabMap: vocabMap,
            grammarMap: grammarMap,
            existing: lessons,
            context: context
        )
        _ = try upsertExercises(
            bundle.lessons,
            lessons: lessonMap,
            vocabMap: vocabMap,
            existing: exercises,
            context: context
        )

        try context.save()
    }

    // MARK: - Prefetch

    /// Fetches all existing entities of a type and indexes them by stable key.
    private static func prefetch<T: PersistentModel & KeyedContent>(
        _ type: T.Type,
        context: ModelContext
    ) throws -> [String: T] {
        let all = try context.fetch(FetchDescriptor<T>())
        var dict: [String: T] = [:]
        for entity in all {
            dict[entity.key] = entity
        }
        return dict
    }

    private static func prefetchLanguages(
        context: ModelContext
    ) throws -> [String: Language] {
        let all = try context.fetch(FetchDescriptor<Language>())
        var dict: [String: Language] = [:]
        for lang in all {
            dict[lang.code] = lang
        }
        return dict
    }

    // MARK: - Language

    private static func findOrCreateLanguage(
        code: String,
        languages: [String: Language],
        context: ModelContext
    ) -> Language {
        if let existing = languages[code] {
            return existing
        }
        let lang = Language(code: code, displayNameKey: "language.\(code)", isoRegion: code)
        context.insert(lang)
        return lang
    }

    // MARK: - Course

    private static func upsertCourse(
        dto: CourseContentDTO,
        source: Language,
        target: Language,
        existing: [String: Course],
        context: ModelContext
    ) throws -> Course {
        let course: Course
        if let found = existing[dto.key] {
            course = found
        } else {
            course = Course(key: dto.key)
            context.insert(course)
        }
        course.titleKey = dto.titleKey
        course.version = dto.version
        course.sourceLanguage = source
        course.targetLanguage = target
        return course
    }

    // MARK: - Levels

    private static func upsertLevels(
        _ dtos: [LevelContentDTO],
        course: Course,
        existing: [String: Level],
        context: ModelContext
    ) throws -> [String: Level] {
        var map = existing
        for dto in dtos {
            let level: Level
            if let found = map[dto.key] {
                level = found
            } else {
                level = Level(key: dto.key, cefr: dto.cefr, orderIndex: dto.orderIndex)
                context.insert(level)
                map[dto.key] = level
            }
            level.cefr = dto.cefr
            level.orderIndex = dto.orderIndex
            level.course = course
            if !course.levels.contains(where: { $0.key == level.key }) {
                course.levels.append(level)
            }
        }
        return map
    }

    // MARK: - Units

    private static func upsertUnits(
        _ dtos: [UnitContentDTO],
        levels: [String: Level],
        existing: [String: Unit],
        context: ModelContext
    ) throws -> [String: Unit] {
        var map = existing
        for dto in dtos {
            let unit: Unit
            if let found = map[dto.key] {
                unit = found
            } else {
                unit = Unit(
                    key: dto.key,
                    orderIndex: dto.orderIndex,
                    titleKey: dto.titleKey,
                    theme: dto.theme,
                    summaryKey: dto.summaryKey
                )
                context.insert(unit)
                map[dto.key] = unit
            }
            unit.orderIndex = dto.orderIndex
            unit.titleKey = dto.titleKey
            unit.theme = dto.theme
            unit.summaryKey = dto.summaryKey
            unit.level = levels[dto.levelKey]
            if let level = levels[dto.levelKey], !level.units.contains(where: { $0.key == unit.key }) {
                level.units.append(unit)
            }
        }
        return map
    }

    // MARK: - Lessons

    private static func upsertLessons(
        _ dtos: [LessonContentDTO],
        units: [String: Unit],
        vocabMap: [String: VocabularyItem],
        grammarMap: [String: GrammarTopic],
        existing: [String: Lesson],
        context: ModelContext
    ) throws -> [String: Lesson] {
        var map = existing
        for dto in dtos {
            let lesson: Lesson
            if let found = map[dto.key] {
                lesson = found
            } else {
                lesson = Lesson(
                    key: dto.key,
                    orderIndex: dto.orderIndex,
                    titleKey: dto.titleKey,
                    kind: dto.kind
                )
                context.insert(lesson)
                map[dto.key] = lesson
            }
            lesson.orderIndex = dto.orderIndex
            lesson.titleKey = dto.titleKey
            lesson.kind = dto.kind
            lesson.unit = units[dto.unitKey]
            if let unit = units[dto.unitKey], !unit.lessons.contains(where: { $0.key == lesson.key }) {
                unit.lessons.append(lesson)
            }
            lesson.vocabulary = dto.vocabularyKeys.compactMap { vocabMap[$0] }
            lesson.grammarTopics = dto.grammarKeys.compactMap { grammarMap[$0] }
        }
        return map
    }

    // MARK: - Exercises

    private static func upsertExercises(
        _ lessonDTOs: [LessonContentDTO],
        lessons: [String: Lesson],
        vocabMap: [String: VocabularyItem],
        existing: [String: Exercise],
        context: ModelContext
    ) throws -> [String: Exercise] {
        var map = existing
        for lessonDTO in lessonDTOs {
            guard let lesson = lessons[lessonDTO.key] else { continue }
            for dto in lessonDTO.exercises {
                let exercise: Exercise
                if let found = map[dto.key] {
                    exercise = found
                } else {
                    exercise = Exercise(
                        key: dto.key,
                        orderIndex: dto.orderIndex,
                        type: dto.type
                    )
                    context.insert(exercise)
                    map[dto.key] = exercise
                }
                exercise.orderIndex = dto.orderIndex
                exercise.type = dto.type
                exercise.promptKey = dto.promptKey
                exercise.promptText = dto.promptText
                exercise.hintKey = dto.hintKey
                exercise.correctAnswerText = dto.correctAnswerText
                exercise.acceptedAnswers = dto.acceptedAnswers
                exercise.lesson = lesson
                if !lesson.exercises.contains(where: { $0.key == exercise.key }) {
                    lesson.exercises.append(exercise)
                }
                exercise.vocabulary = dto.vocabularyKeys.compactMap { vocabMap[$0] }
                exercise.payloadData = encodePayload(dto.payload)
            }
        }
        return map
    }

    // MARK: - Vocabulary

    private static func upsertVocabulary(
        _ dtos: [VocabularyContentDTO],
        existing: [String: VocabularyItem],
        context: ModelContext
    ) throws -> [String: VocabularyItem] {
        var map = existing
        for dto in dtos {
            let vocab: VocabularyItem
            if let found = map[dto.key] {
                vocab = found
            } else {
                vocab = VocabularyItem(
                    key: dto.key,
                    sourceText: dto.sourceText,
                    targetText: dto.targetText,
                    partOfSpeech: dto.partOfSpeech,
                    cefr: dto.cefr
                )
                context.insert(vocab)
                map[dto.key] = vocab
            }
            vocab.sourceText = dto.sourceText
            vocab.targetText = dto.targetText
            vocab.pronunciation = dto.pronunciation
            vocab.partOfSpeech = dto.partOfSpeech
            vocab.cefr = dto.cefr
            vocab.exampleSource = dto.exampleSource
            vocab.exampleTarget = dto.exampleTarget
            vocab.difficulty = dto.difficulty
            vocab.imageAsset = dto.imageAsset
            vocab.audioFileName = dto.audioFileName
        }
        return map
    }

    // MARK: - Grammar

    private static func upsertGrammar(
        _ dtos: [GrammarContentDTO],
        existing: [String: GrammarTopic],
        context: ModelContext
    ) throws -> [String: GrammarTopic] {
        var map = existing
        for dto in dtos {
            let grammar: GrammarTopic
            if let found = map[dto.key] {
                grammar = found
            } else {
                grammar = GrammarTopic(
                    key: dto.key,
                    titleKey: dto.titleKey,
                    explanationKey: dto.explanationKey,
                    examples: dto.examples,
                    cefr: dto.cefr
                )
                context.insert(grammar)
                map[dto.key] = grammar
            }
            grammar.titleKey = dto.titleKey
            grammar.explanationKey = dto.explanationKey
            grammar.examples = dto.examples
            grammar.cefr = dto.cefr
        }
        return map
    }

    // MARK: - Helpers

    private static func encodePayload(_ value: JSONValue?) -> Data? {
        guard let value, !isNull(value) else { return nil }
        return try? JSONEncoder().encode(value)
    }

    private static func isNull(_ value: JSONValue) -> Bool {
        if case .null = value { return true }
        return false
    }
}
