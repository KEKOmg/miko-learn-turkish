import Foundation
import CoreText
import UIKit
import Testing
@testable import Miko

struct FontRegistrationTests {

    @Test func lexendFamilyResolves() {
        FontRegistrar.registerFonts()

        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Lexend",
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]
        ])
        let font = UIFont(descriptor: descriptor, size: 16)

        #expect(font.fontName.contains("Lexend"), "Expected Lexend to resolve, got \(font.fontName)")
    }
}
