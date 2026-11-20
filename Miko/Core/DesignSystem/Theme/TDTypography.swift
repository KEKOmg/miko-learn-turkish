import SwiftUI

/// Centralized typography styles. All text in feature code should use these
/// styles (directly or via the text modifiers) rather than raw font calls.
enum TDTypography {

    static let largeTitle = Font.lexend(.bold, size: 32, relativeTo: .largeTitle)
    static let title = Font.lexend(.bold, size: 28, relativeTo: .title)
    static let sectionTitle = Font.lexend(.semibold, size: 22, relativeTo: .title2)
    static let cardTitle = Font.lexend(.semibold, size: 18, relativeTo: .headline)
    static let body = Font.lexend(.regular, size: 16, relativeTo: .body)
    static let secondary = Font.lexend(.regular, size: 14, relativeTo: .subheadline)
    static let button = Font.lexend(.semibold, size: 17, relativeTo: .headline)
    static let caption = Font.lexend(.regular, size: 13, relativeTo: .caption)
}
