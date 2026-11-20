import Foundation
import Testing
@testable import Miko

struct TurkishTextNormalizerTests {

    @Test func whitespaceTrimming() {
        #expect(TurkishTextNormalizer.normalize("  merhaba  ") == "merhaba")
    }

    @Test func whitespaceCollapsing() {
        #expect(TurkishTextNormalizer.normalize("merhaba   dünya") == "merhaba dünya")
    }

    @Test func turkishDottedI() {
        #expect(TurkishTextNormalizer.normalize("İstanbul") == "istanbul")
    }

    @Test func turkishDotlessI() {
        #expect(TurkishTextNormalizer.normalize("Istanbul") == "ıstanbul")
    }

    @Test func lowercaseI() {
        #expect(TurkishTextNormalizer.normalize("istanbul") == "istanbul")
    }

    @Test func lowercaseDotlessI() {
        #expect(TurkishTextNormalizer.normalize("ıstanbul") == "ıstanbul")
    }

    @Test func diacriticFolding() {
        #expect(TurkishTextNormalizer.foldTurkishDiacritics("şğçöü") == "sgcou")
    }

    @Test func diacriticFoldingCapital() {
        #expect(TurkishTextNormalizer.foldTurkishDiacritics("ŞĞÇÖÜ") == "sgcou")
    }

    @Test func lenientNormalizationMatchesDiacritics() {
        let a = TurkishTextNormalizer.normalizeLenient("Merhaba!")
        let b = TurkishTextNormalizer.normalizeLenient("merhaba")
        #expect(a == b)
    }

    @Test func lenientNormalizationPreservesDottedAndDotlessI() {
        #expect(TurkishTextNormalizer.normalizeLenient("İstanbul") == "istanbul")
        #expect(TurkishTextNormalizer.normalizeLenient("Istanbul") == "ıstanbul")
        #expect(TurkishTextNormalizer.normalizeLenient("sık") != TurkishTextNormalizer.normalizeLenient("sik"))
    }

    @Test func trailingPunctuationStripped() {
        #expect(TurkishTextNormalizer.normalize("Merhaba!") == "merhaba")
        #expect(TurkishTextNormalizer.normalize("Nasılsın?") == "nasılsın")
    }

    @Test func lenientNormalizationStripsAllPunctuation() {
        let a = TurkishTextNormalizer.normalizeLenient("Mer-ha-ba!")
        #expect(a == "merhaba")
    }

    @Test func lenientNormalizationDoesNotMergeDistinctWords() {
        #expect(TurkishTextNormalizer.normalizeLenient("bir şey") == "bir sey")
        #expect(TurkishTextNormalizer.normalizeLenient("bir şey") !=
                TurkishTextNormalizer.normalizeLenient("birşey"))
        #expect(TurkishTextNormalizer.normalizeLenient("  iki   çocuk  ") == "iki cocuk")
    }
}
