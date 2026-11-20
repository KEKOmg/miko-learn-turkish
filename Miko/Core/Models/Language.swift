import Foundation
import SwiftData

@Model
final class Language {
    @Attribute(.unique) var code: String
    var displayNameKey: String
    var isoRegion: String

    init(code: String, displayNameKey: String, isoRegion: String) {
        self.code = code
        self.displayNameKey = displayNameKey
        self.isoRegion = isoRegion
    }
}