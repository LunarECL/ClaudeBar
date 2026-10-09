import Foundation
import Mockable

/// A JavaScript engine, for a `script` mapping (MODULAR_DESIGN §6). Each run
/// gets a fresh context with no file, network or process access: a mapping
/// script turns text into numbers and nothing else. The Mac's is
/// JavaScriptCore; a platform with none has no `scriptEngine` (§10).
@Mockable
protocol ScriptEngine: Sendable {
    /// Loads `scripts` in order into a fresh context that holds `strings` as
    /// global text and `functions` as global functions from text to a number
    /// or `null`, then evaluates `expression`. Answers its value as text, or
    /// `nil` when it is `undefined`.
    ///
    /// Throws `ScriptEngineError.load` when a script throws while loading,
    /// and `.run` when `expression` throws.
    func evaluate(_ expression: String, after scripts: [String], strings: [String: String],
                  functions: [String: ScriptFunction]) throws -> String?
}

/// A host function a script may call: text in, a number or `null` out.
typealias ScriptFunction = @Sendable (String) -> Double?

/// What a script threw, as the engine reports it.
enum ScriptEngineError: Error, Equatable {
    case load(String)
    case run(String)
}
