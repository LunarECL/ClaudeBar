#if os(Windows)
import Foundation

extension Platform {
    /// ClaudeBar for Windows so far (MODULAR_DESIGN §10): it finds a CLI on
    /// `PATH`, and has no other connection yet. Each case that needs one fails
    /// at its step, naming it and Windows; phase 5 fills them in.
    static let current = Platform(name: "Windows", binaryLocator: PathBinaryLocator())
}
#endif
