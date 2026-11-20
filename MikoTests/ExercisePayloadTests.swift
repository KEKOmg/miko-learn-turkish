import Foundation
import Testing
@testable import Miko

struct ExercisePayloadTests {

    @Test func multipleChoicePayloadRoundTrip() throws {
        let payload = MultipleChoicePayload(options: ["a", "b", "c"], correctIndex: 1)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(MultipleChoicePayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test func buildSentencePayloadRoundTrip() throws {
        let payload = BuildSentencePayload(wordBank: ["Ben", "geliyorum"], sentenceWords: ["Ben", "geliyorum"])
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(BuildSentencePayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test func matchPairsPayloadRoundTrip() throws {
        let payload = MatchPairsPayload(pairs: [
            MatchPair(source: "Привет", target: "Merhaba"),
            MatchPair(source: "Пока", target: "Hoşça kal")
        ])
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(MatchPairsPayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test func matchPairsBoardAvoidsStraightAndCornerShortcuts() throws {
        let pairs = [
            MatchPair(source: "один", target: "bir"),
            MatchPair(source: "два", target: "iki"),
            MatchPair(source: "три", target: "üç"),
            MatchPair(source: "четыре", target: "dört")
        ]
        let targetBySource = Dictionary(uniqueKeysWithValues: pairs.map { ($0.source, $0.target) })

        for _ in 0..<50 {
            let layout = MatchPairsBoardLayout.make(from: pairs)
            let expectedTargets = try layout.sources.map { source in
                try #require(targetBySource[source])
            }
            let hasSameRowMatch = zip(expectedTargets, layout.targets).contains { expected, displayed in
                expected == displayed
            }

            #expect(Set(layout.sources) == Set(pairs.map(\.source)))
            #expect(Set(layout.targets) == Set(pairs.map(\.target)))
            #expect(!hasSameRowMatch)
            #expect(expectedTargets.first != layout.targets.last)
        }
    }

    @Test func fillBlankPayloadRoundTrip() throws {
        let payload = FillBlankPayload(template: "Ben ___ öğrenciyim.", blank: "bir", options: ["bir", "iki", "üç"])
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(FillBlankPayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test func listeningPayloadRoundTrip() throws {
        let payload = ListeningComprehensionPayload(audioFileName: "merhaba.mp3", transcript: "Merhaba!", options: ["Привет", "Пока"], correctIndex: 1)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ListeningComprehensionPayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test func translateWordPayloadRoundTrip() throws {
        let payload = TranslateWordPayload()
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(TranslateWordPayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test func translateSentencePayloadRoundTrip() throws {
        let payload = TranslateSentencePayload()
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(TranslateSentencePayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test func pronunciationPayloadRoundTrip() throws {
        let payload = PronunciationPayload()
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PronunciationPayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test func vocabularyReviewPayloadRoundTrip() throws {
        let payload = VocabularyReviewPayload()
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(VocabularyReviewPayload.self, from: data)
        #expect(decoded == payload)
    }

    // MARK: - FillBlank placeholder parsing (HIGH-5)

    @Test func fillBlankSplitsCanonicalFourUnderscorePlaceholder() throws {
        let parts = try #require(FillBlankPayload.split(template: "Taze ____, lütfen."))
        #expect(parts.prefix == "Taze ")
        #expect(parts.suffix == ", lütfen.")
    }

    /// Rendering is tolerant: a 3-underscore run must still produce a blank.
    @Test func fillBlankSplitsThreeUnderscorePlaceholder() throws {
        let parts = try #require(FillBlankPayload.split(template: "___ dakika, lütfen."))
        #expect(parts.prefix == "")
        #expect(parts.suffix == " dakika, lütfen.")
    }

    @Test func fillBlankSplitsLongUnderscoreRun() throws {
        let parts = try #require(FillBlankPayload.split(template: "Ben ________ öğrenciyim."))
        #expect(parts.prefix == "Ben ")
        #expect(parts.suffix == " öğrenciyim.")
    }

    @Test func fillBlankSplitsPlaceholderAtEndOfTemplate() throws {
        let parts = try #require(FillBlankPayload.split(template: "Ben ____"))
        #expect(parts.prefix == "Ben ")
        #expect(parts.suffix == "")
    }

    @Test func fillBlankRejectsTooShortUnderscoreRun() {
        #expect(FillBlankPayload.split(template: "Ben __ öğrenciyim.") == nil)
        #expect(FillBlankPayload.split(template: "Ben _ öğrenciyim.") == nil)
        #expect(FillBlankPayload.hasPlaceholder(in: "Ben __ öğrenciyim.") == false)
    }

    @Test func fillBlankRejectsTemplateWithoutPlaceholder() {
        #expect(FillBlankPayload.split(template: "Ben öğrenciyim.") == nil)
        #expect(FillBlankPayload.hasPlaceholder(in: "Ben öğrenciyim.") == false)
    }

    @Test func fillBlankHasPlaceholderAcceptsCanonicalForm() {
        #expect(FillBlankPayload.hasPlaceholder(in: "Ben ____ öğrenciyim.") == true)
    }

    /// A short run before a valid run must not defeat detection.
    @Test func fillBlankIgnoresShortRunBeforeValidPlaceholder() throws {
        let parts = try #require(FillBlankPayload.split(template: "a_b ____ c"))
        #expect(parts.prefix == "a_b ")
        #expect(parts.suffix == " c")
    }

    @Test func malformedPayloadDataReturnsNil() {
        let badData = Data([0x00, 0xFF])
        let decoded = try? JSONDecoder().decode(MultipleChoicePayload.self, from: badData)
        #expect(decoded == nil)
    }

    @Test func emptyPayloadDataReturnsNil() {
        let decoded = try? JSONDecoder().decode(MultipleChoicePayload.self, from: Data())
        #expect(decoded == nil)
    }
}
