import SwiftUI

enum LexendWeight {
    case regular
    case semibold
    case bold

    var uiFontWeight: UIFont.Weight {
        switch self {
        case .regular: return .regular
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

extension Font {
    /// Creates a Lexend font at the given size, resolved against the variable
    /// font's weight axis. Falls back to the system font if Lexend is missing.
    static func lexend(_ weight: LexendWeight, size: CGFloat) -> Font {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Lexend",
            .traits: [UIFontDescriptor.TraitKey.weight: weight.uiFontWeight]
        ])
        return Font(UIFont(descriptor: descriptor, size: size))
    }

    /// Creates a Lexend font that scales with Dynamic Type for the given style.
    static func lexend(
        _ weight: LexendWeight,
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Lexend",
            .traits: [UIFontDescriptor.TraitKey.weight: weight.uiFontWeight]
        ])
        let base = UIFont(descriptor: descriptor, size: size)
        let scaled = UIFontMetrics(forTextStyle: textStyle.uiTextStyle).scaledFont(for: base)
        return Font(scaled)
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}
