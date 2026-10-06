import Foundation
import CoreText

/// A font shipped in Resources/Fonts, registered for this process the first
/// time a theme asks for it.
enum BundledFont {
    /// Registers `file`.ttf and returns the font's `name`, or `nil` if it
    /// can't be registered — the system font then stands in.
    static func register(file: String, name: String) -> String? {
        guard let url = Bundle.main.url(forResource: file, withExtension: "ttf") else { return nil }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Already registered is fine; anything else falls back.
            let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? 0
            if code != CTFontManagerError.alreadyRegistered.rawValue { return nil }
        }
        return name
    }
}
