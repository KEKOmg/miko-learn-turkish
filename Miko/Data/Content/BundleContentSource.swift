import Foundation

/// Aggregates all seed content DTOs after loading from the bundle.
struct ContentBundle: Equatable {
    let course: CourseContentDTO
    let levels: [LevelContentDTO]
    let units: [UnitContentDTO]
    let lessons: [LessonContentDTO]
    let vocabulary: [VocabularyContentDTO]
    let grammar: [GrammarContentDTO]
}

/// Reads the bundled JSON seed files and produces `ContentBundle`.
struct BundleContentSource {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func load() throws -> ContentBundle {
        let course = try decodeResource(CourseContentDTO.self, named: "course")
        let levels = try decodeMany(LevelContentDTO.self, prefix: "level-")
        let units = try decodeMany(UnitContentDTO.self, prefix: "unit-")
        let lessons = try decodeMany(LessonContentDTO.self, prefix: "lesson-")
        let vocabulary = try decodeMany(VocabularyContentDTO.self, named: "vocabulary")
        let grammar = try decodeMany(GrammarContentDTO.self, named: "grammar")

        return ContentBundle(
            course: course,
            levels: levels,
            units: units,
            lessons: lessons,
            vocabulary: vocabulary,
            grammar: grammar
        )
    }

    // MARK: - Private

    private func decodeResource<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: nil) else {
            throw ContentError.missingFile("\(name).json")
        }
        return try decode(url: url, as: type)
    }

    private func decodeMany<T: Decodable>(
        _ type: T.Type,
        prefix: String
    ) throws -> [T] {
        let allUrls = bundle.urls(
            forResourcesWithExtension: "json",
            subdirectory: nil
        ) ?? []

        let matching = allUrls
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try matching.map { try decode(url: $0, as: type) }
    }

    private func decodeMany<T: Decodable>(
        _ type: T.Type,
        named name: String
    ) throws -> [T] {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: nil) else {
            throw ContentError.missingFile("\(name).json")
        }
        return try decode(url: url, as: [T].self)
    }

    private func decode<T: Decodable>(url: URL, as type: T.Type) throws -> T {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch {
            let name = url.lastPathComponent
            throw ContentError.decoding(name, error.localizedDescription)
        }
    }}