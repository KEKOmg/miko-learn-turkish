import Foundation
import CoreText

enum FontRegistrar {

    /// Registers bundled fonts with CoreText. Safe to call more than once.
    static func registerFonts() {
        register(named: "Lexend.ttf")
    }

    private static func register(named filename: String) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else {
            assertionFailure("Bundled font missing: \(filename)")
            return
        }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }
}
