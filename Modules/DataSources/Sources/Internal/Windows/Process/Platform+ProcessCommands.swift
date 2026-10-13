#if os(Windows)
import Foundation

extension Platform {
    static let windowsScriptCommand: ScriptCommand = { run in
        let preferred = ProcessInfo.processInfo.environment["ComSpec"] ?? ""
        let binary = preferred.isEmpty ? "cmd.exe" : preferred
        return [binary, "/d", "/s", "/c", run]
    }
}
#endif
