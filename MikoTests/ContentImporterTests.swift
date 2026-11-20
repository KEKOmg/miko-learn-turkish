import Foundation
import SwiftData
import Testing
@testable import Miko

@MainActor
@Suite(.serialized)
struct ContentImporterTests {
    typealias LearningUnit = Miko.Unit

    @Test func importsCompleteCourse() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bundle = try ContentTestSupport.loadBundle()

        try ContentImporter.import(bundle, into: context)

        let courses = try context.fetch(FetchDescriptor<Course>())
        let levels = try context.fetch(FetchDescriptor<Level>())
        let units = try context.fetch(FetchDescriptor<LearningUnit>())
        let lessons = try context.fetch(FetchDescriptor<Lesson>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let vocab = try context.fetch(FetchDescriptor<VocabularyItem>())
        let grammar = try context.fetch(FetchDescriptor<GrammarTopic>())
        let languages = try context.fetch(FetchDescriptor<Language>())

        #expect(courses.count == 1)
        #expect(levels.count == 2)
        #expect(units.count == 14)
        #expect(lessons.count == 28)
        #expect(exercises.count == 217)
        #expect(vocab.count == 230)
        #expect(grammar.count == 19)
        #expect(languages.count == 2)
    }

    @Test func importIsIdempotent() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bundle = try ContentTestSupport.loadBundle()

        try ContentImporter.import(bundle, into: context)
        let firstCount = try context.fetchCount(FetchDescriptor<Exercise>())
        let firstVocab = try context.fetchCount(FetchDescriptor<VocabularyItem>())

        try ContentImporter.import(bundle, into: context)
        let secondCount = try context.fetchCount(FetchDescriptor<Exercise>())
        let secondVocab = try context.fetchCount(FetchDescriptor<VocabularyItem>())

        #expect(firstCount == secondCount)
        #expect(firstVocab == secondVocab)
        #expect(try context.fetchCount(FetchDescriptor<Course>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Level>()) == 2)
    }

    @Test func incompleteSameVersionCourseGraphIsDetected() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bundle = try ContentTestSupport.loadBundle()
        try ContentImporter.import(bundle, into: context)

        let course = try #require(
            try CourseRepository(context: context).fetchCourse(byKey: "course.ru-tr")
        )
        #expect(ContentBootstrap.hasCompleteCourseGraph(course, for: bundle))

        course.levels.removeAll { $0.key == "a2" }
        #expect(!ContentBootstrap.hasCompleteCourseGraph(course, for: bundle))
    }

    @Test func importUpdatesExistingContent() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bundle = try ContentTestSupport.loadBundle()
        try ContentImporter.import(bundle, into: context)

        var updatedVocab = bundle.vocabulary
        let index = updatedVocab.firstIndex { $0.key == "vocab.merhaba" }!
        updatedVocab[index] = VocabularyContentDTO(
            key: "vocab.merhaba", sourceText: "Привет", targetText: "Merhaba!",
            pronunciation: "mer-ha-ba", partOfSpeech: .interjection, cefr: .a1,
            exampleSource: "", exampleTarget: "", difficulty: 1, imageAsset: nil, audioFileName: nil
        )

        let updatedBundle = ContentBundle(
            course: bundle.course, levels: bundle.levels, units: bundle.units,
            lessons: bundle.lessons, vocabulary: updatedVocab, grammar: bundle.grammar
        )
        try ContentImporter.import(updatedBundle, into: context)

        let vocab = try context.fetch(FetchDescriptor<VocabularyItem>())
        #expect(vocab.count == 230)
        let merhaba = vocab.first { $0.key == "vocab.merhaba" }
        #expect(merhaba?.targetText == "Merhaba!")
    }

    @Test func establishesRelationships() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bundle = try ContentTestSupport.loadBundle()
        try ContentImporter.import(bundle, into: context)

        let repo = CourseRepository(context: context)
        let course = try repo.fetchCourse(byKey: "course.ru-tr")
        #expect(course != nil, "Course not found")

        let levels = try repo.fetchLevels(for: course!)
        #expect(levels.count == 2, "Expected 2 levels, got \(levels.count)")

        let units = try repo.fetchUnits(for: levels[0])
        #expect(units.count == 7, "Expected 7 units, got \(units.count)")

        let lessons = try repo.fetchLessons(for: units[0])
        #expect(lessons.count == 2, "Expected 2 lessons, got \(lessons.count)")

        let exercises = try repo.fetchExercises(for: lessons[0])
        #expect(exercises.count == 8, "Expected 8 exercises, got \(exercises.count)")

        #expect(!lessons[0].vocabulary.isEmpty, "Lesson 0 vocabulary empty")
        #expect(!lessons[1].grammarTopics.isEmpty, "Lesson 1 grammar empty")
    }

    @Test func courseLanguagesAreRuTr() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bundle = try ContentTestSupport.loadBundle()
        try ContentImporter.import(bundle, into: context)

        let course = try CourseRepository(context: context).fetchCourse(byKey: "course.ru-tr")
        #expect(course?.sourceLanguage?.code == "ru")
        #expect(course?.targetLanguage?.code == "tr")
    }

    @Test func allExerciseTypesImported() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bundle = try ContentTestSupport.loadBundle()
        try ContentImporter.import(bundle, into: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let types = Set(exercises.map(\.type))
        #expect(types == Set(ExerciseType.allCases))
    }

    @Test func exercisePayloadStoredAsData() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bundle = try ContentTestSupport.loadBundle()
        try ContentImporter.import(bundle, into: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let multipleChoice = exercises.first { $0.type == .multipleChoice && $0.key == "a1.u1.l1.e1" }
        #expect(multipleChoice != nil)
        #expect(multipleChoice?.payloadData != nil)

        if let data = multipleChoice?.payloadData {
            let payload = try JSONDecoder().decode(MultipleChoicePayload.self, from: data)
            #expect(payload.options.count == 4)
        }
    }

    @Test func vocabularyReviewExercisesKeepVocabularyRelationships() throws {
        let container = try ContentTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let bundle = try ContentTestSupport.loadBundle()
        try ContentImporter.import(bundle, into: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let reviews = exercises.filter { $0.type == .vocabularyReview }

        #expect(!reviews.isEmpty)
        for review in reviews {
            #expect(!review.vocabulary.isEmpty, "Vocabulary is missing for \(review.key)")
        }
    }
}
