import Testing
@testable import DataSources

/// What a test needs from the platform (MODULAR_DESIGN §10). It runs wherever
/// `Platform.current` has that connection and is skipped elsewhere, saying
/// why, so the phase that brings a connection starts its tests with no edit.
extension Trait where Self == ConditionTrait {
    /// Runs a definition's `script` mapping.
    static var needsScriptEngine: Self {
        .enabled(if: Platform.current.scriptEngine != nil,
                 "runs a mapping script: \(Platform.current.name) has no script engine yet (phase 5)")
    }

    /// Runs a CLI, a command or a script, or reads a CLI's screen.
    static var needsProcesses: Self {
        .enabled(if: Platform.current.runCommand != nil,
                 "runs a process: \(Platform.current.name) runs none yet (phase 5)")
    }

    /// Makes its database with `sqlite3` and reads it with the platform's SQLite.
    static var needsSQLite: Self {
        .enabled(if: Platform.current.sqlite != nil,
                 "uses SQLite: \(Platform.current.name) has none yet (phase 5)")
    }
}
