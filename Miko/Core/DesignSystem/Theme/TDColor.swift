import SwiftUI

/// Centralized color system for Miko.
///
/// Raw palette colors are the brand identity. Semantic colors are the colors
/// that feature code should actually consume, so that future tweaks to the
/// brand palette do not require touching feature screens.
enum TDColor {

    // MARK: - Brand palette

    static let tealDark = Color(hex: "0D3B3E")
    static let teal = Color(hex: "177E7A")
    static let coral = Color(hex: "F25D5D")
    static let cream = Color(hex: "F7E9D1")
    static let mint = Color(hex: "E6F4F1")
    static let gold = Color(hex: "FFCB57")
    static let white = Color(hex: "FFFFFF")

    // Dark-mode support surfaces.
    static let ink = Color(hex: "102022")
    static let surfaceDark = Color(hex: "1B3436")
    static let surfaceDarkElevated = Color(hex: "254447")

    // MARK: - Semantic colors

    static let primary = teal
    static let primaryDark = tealDark

    /// App background. Warm cream in light mode, deep teal-tinted in dark mode.
    static let background = Color(light: cream, dark: ink)

    /// Elevated card surface. White in light mode, dark slate in dark mode.
    static let surface = Color(light: white, dark: surfaceDark)

    /// Secondary / subtle surface. Soft mint in light mode.
    static let secondarySurface = Color(light: mint, dark: surfaceDarkElevated)

    static let success = Color(light: Color(hex: "2E8B6E"), dark: Color(hex: "4BC39A"))
    static let error = coral
    static let warning = Color(light: Color(hex: "E0A63A"), dark: gold)

    static let textPrimary = Color(light: tealDark, dark: cream)
    static let textSecondary = Color(light: Color(hex: "5A6B6D"), dark: Color(hex: "A9C2C3"))
    static let textOnPrimary = white

    /// High-emphasis screen and brand titles. Unlike `primaryDark`, this
    /// remains clearly visible on the app's dark background.
    static let screenTitle = Color(light: tealDark, dark: Color(hex: "8FE3D6"))

    /// Muted text placed on deep teal surfaces (e.g. the tab bar).
    static let onDarkMuted = Color(hex: "9DC0BE")

    static let disabled = Color(light: Color(hex: "C8D6D4"), dark: Color(hex: "2C4749"))
    static let disabledText = Color(light: Color(hex: "8AA09E"), dark: Color(hex: "6E8B89"))
}
