#if os(macOS)
import Foundation
import JavaScriptCore
import Quotas

/// The Mac's script engine: a fresh `JSContext` for each run.
struct JavaScriptCoreEngine: ScriptEngine {
    func evaluate(_ expression: String, after scripts: [String], strings: [String: String],
                  functions: [String: ScriptFunction]) throws -> String? {
        guard let context = JSContext() else {
            throw UsageError.executionFailed("JavaScriptCore is unavailable")
        }
        var exception: String?
        context.exceptionHandler = { _, value in
            exception = value?.toString()
        }
        for (name, function) in functions {
            let block: @convention(block) (String) -> Any = { function($0) ?? NSNull() }
            context.setObject(block, forKeyedSubscript: name as NSString)
        }
        for (name, text) in strings {
            context.setObject(text, forKeyedSubscript: name as NSString)
        }
        for script in scripts {
            context.evaluateScript(script)
        }
        if let exception {
            throw ScriptEngineError.load(exception)
        }
        let value = context.evaluateScript(expression)
        if let exception {
            throw ScriptEngineError.run(exception)
        }
        guard let text = value?.toString(), text != "undefined" else { return nil }
        return text
    }
}
#endif
