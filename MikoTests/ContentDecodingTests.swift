import Foundation
import Testing
@testable import Miko

@Suite(.serialized)
struct ContentDecodingTests {

    @Test func bundleLoadsSuccessfully() throws {
        let bundle = try ContentTestSupport.loadBundle()
        #expect(bundle.course.key == "course.ru-tr")
        #expect(bundle.levels.count == 2)
        #expect(bundle.units.count == 14)
        #expect(bundle.lessons.count == 28)
        #expect(bundle.vocabulary.count == 230)
        #expect(bundle.grammar.count == 19)
    }

    @Test func courseHasCorrectLanguages() throws {
        let bundle = try ContentTestSupport.loadBundle()
        #expect(bundle.course.sourceLanguageCode == "ru")
        #expect(bundle.course.targetLanguageCode == "tr")
    }

    @Test func allExerciseTypesRepresented() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let types = Set(bundle.lessons.flatMap { $0.exercises.map(\.type) })
        for expected in ExerciseType.allCases {
            #expect(types.contains(expected), "Missing exercise type: \(expected.rawValue)")
        }
    }

    @Test func exercisesPerLesson() throws {
        let bundle = try ContentTestSupport.loadBundle()
        for lesson in bundle.lessons {
            #expect(lesson.exercises.count >= 6, "Lesson \(lesson.key) has fewer than 6 exercises")
        }
    }

    @Test func vocabularyHasRequiredFields() throws {
        let bundle = try ContentTestSupport.loadBundle()
        for vocab in bundle.vocabulary {
            #expect(!vocab.sourceText.trimmingCharacters(in: .whitespaces).isEmpty,
                    "vocab \(vocab.key) has empty sourceText")
            #expect(!vocab.targetText.trimmingCharacters(in: .whitespaces).isEmpty,
                    "vocab \(vocab.key) has empty targetText")
            #expect(!vocab.key.isEmpty)
        }
    }

    @Test func jsonPayloadsDecodeValid() throws {
        let bundle = try ContentTestSupport.loadBundle()
        let decoder = JSONDecoder()
        for lesson in bundle.lessons {
            for exercise in lesson.exercises {
                switch exercise.type {
                case .multipleChoice:
                    if let p = exercise.payload {
                        let data = try JSONEncoder().encode(p)
                        let mp = try decoder.decode(MultipleChoicePayload.self, from: data)
                        #expect(!mp.options.isEmpty)
                        #expect(mp.correctIndex >= 0 && mp.correctIndex < mp.options.count)
                    }
                case .buildSentence:
                    if let p = exercise.payload {
                        let data = try JSONEncoder().encode(p)
                        let bp = try decoder.decode(BuildSentencePayload.self, from: data)
                        let wordSet = Set(bp.wordBank)
                        #expect(bp.sentenceWords.allSatisfy { wordSet.contains($0) })
                    }
                case .matchPairs:
                    if let p = exercise.payload {
                        let data = try JSONEncoder().encode(p)
                        let mp = try decoder.decode(MatchPairsPayload.self, from: data)
                        #expect(!mp.pairs.isEmpty)
                    }
                case .fillBlank:
                    if let p = exercise.payload {
                        let data = try JSONEncoder().encode(p)
                        let fp = try decoder.decode(FillBlankPayload.self, from: data)
                        #expect(!fp.options.isEmpty)
                        #expect(!fp.blank.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                case .listeningComprehension:
                    if let p = exercise.payload {
                        let data = try JSONEncoder().encode(p)
                        let lp = try decoder.decode(ListeningComprehensionPayload.self, from: data)
                        #expect(!lp.audioFileName.trimmingCharacters(in: .whitespaces).isEmpty)
                        #expect(!lp.options.isEmpty)
                        #expect(lp.correctIndex >= 0)
                        #expect(lp.correctIndex < lp.options.count)
                    }
                default:
                    break
                }
            }
        }
    }
}
