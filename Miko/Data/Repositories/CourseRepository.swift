import Foundation
import SwiftData

struct CourseRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchCourse(byKey key: String) throws -> Course? {
        let predicate = #Predicate<Course> { $0.key == key }
        var descriptor = FetchDescriptor<Course>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchLevels(for course: Course) throws -> [Level] {
        course.levels.sorted { $0.orderIndex < $1.orderIndex }
    }

    func fetchUnits(for level: Level) throws -> [Unit] {
        level.units.sorted { $0.orderIndex < $1.orderIndex }
    }

    func fetchLessons(for unit: Unit) throws -> [Lesson] {
        unit.lessons.sorted { $0.orderIndex < $1.orderIndex }
    }

    func fetchExercises(for lesson: Lesson) throws -> [Exercise] {
        lesson.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    func fetchCourseExists(key: String) throws -> Bool {
        try fetchCourse(byKey: key) != nil
    }

    func fetchAllVocabulary() throws -> [VocabularyItem] {
        try context.fetch(FetchDescriptor<VocabularyItem>())
    }

    func fetchAllGrammar() throws -> [GrammarTopic] {
        try context.fetch(FetchDescriptor<GrammarTopic>())
    }
}
