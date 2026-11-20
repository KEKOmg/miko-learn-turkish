import Foundation

/// Turkish-aware text normalization for answer validation.
///
/// Handles:
/// - whitespace trimming and collapsing
/// - case folding with correct Turkish i / ı / İ / I behavior
/// - punctuation stripping for sentence comparison
/// - diacritic-insensitive fallback for ş/ğ/ç/ö/ü, while preserving the
///   meaning-bearing Turkish distinction between dotted i and dotless ı
enum TurkishTextNormalizer {

    /// Primary normalization: trim, collapse whitespace, fold case respecting
    /// Turkish dotted/dotless i, strip trailing punctuation.
    static func normalize(_ text: String) -> String {
        var result = text
        result = result.trimmingCharacters(in: .whitespaces)
        result = collapseWhitespace(result)
        result = turkishLowercased(result)
        result = stripTrailingPunctuation(result)
        return result
    }

    /// Lenient fallback for punctuation and most Turkish diacritics. Dotted
    /// and dotless i stay distinct: folding ı to i accepts a different word.
    static func normalizeLenient(_ text: String) -> String {
        var result = normalize(text)
        result = removePunctuation(result)
        result = foldTurkishDiacritics(result)
        return result
    }

    // MARK: - Whitespace

    static func collapseWhitespace(_ text: String) -> String {
        var components: [String] = []
        var inWhitespace = false
        for char in text {
            if char.isWhitespace {
                if !inWhitespace {
                    components.append(" ")
                    inWhitespace = true
                }
            } else {
                components.append(String(char))
                inWhitespace = false
            }
        }
        return components.joined()
    }

    // MARK: - Turkish case folding

    /// Lowercases respecting Turkish dotted/dotless i:
    /// - İ (U+0130) → i  (dotted capital I → dotted lowercase i)
    /// - I (U+0049) → ı  (dotless capital I → dotless lowercase ı)
    /// - i (U+0069) → i  (already lowercase dotted i, unchanged)
    /// - ı (U+0131) → ı  (already lowercase dotless ı, unchanged)
    static func turkishLowercased(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for char in text {
            switch char {
            case "İ":
                result.append("i")
            case "I":
                result.append("ı")
            default:
                result.append(char.lowercased())
            }
        }
        return result
    }

    // MARK: - Punctuation

    /// Strips trailing punctuation (period, exclamation, question mark, comma).
    static func stripTrailingPunctuation(_ text: String) -> String {
        var result = text
        while let last = result.last, last.isPunctuation {
            result.removeLast()
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Removes punctuation but keeps word boundaries. Otherwise a spaced
    /// phrase and a different single word can compare equal in lenient mode.
    static func removePunctuation(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) })
    }

    // MARK: - Diacritic folding

    /// Folds ş/ğ/ç/ö/ü to ASCII after Turkish-aware case folding. Never fold
    /// ı to i; those are separate letters and can distinguish real words.
    static func foldTurkishDiacritics(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            ("ş", "s"), ("Ş", "s"),
            ("ğ", "g"), ("Ğ", "g"),
            ("ç", "c"), ("Ç", "c"),
            ("ö", "o"), ("Ö", "o"),
            ("ü", "u"), ("Ü", "u"),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }
}
