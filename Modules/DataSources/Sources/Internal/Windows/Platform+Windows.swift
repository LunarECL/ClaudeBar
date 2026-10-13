#if os(Windows)
import Foundation

extension Platform {
    /// File paths and CLI discovery are available; execution connections stay
    /// absent until phase 5. Missing connections fail at their named step.
    static let current = Platform(
        name: "Windows",
        binaryLocator: PathBinaryLocator(),
        applicationData: { home, environment in
            if let path = environment("APPDATA"), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return home.appendingPathComponent("AppData/Roaming", isDirectory: true)
        },
        pathSeparator: "\\",
        scriptCommand: windowsScriptCommand
    )
}
#endif
