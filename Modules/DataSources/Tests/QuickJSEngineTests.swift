import Foundation
import Testing
@testable import DataSources

/// The one script engine, QuickJS, on every platform (#570): what
/// `ScriptEngine` promises a mapping, run for real.
@Suite
struct QuickJSEngineTests {
    private let engine = QuickJSEngine()

    private func run(_ expression: String, after scripts: [String] = [], strings: [String: String] = [:],
                     functions: [String: ScriptFunction] = [:]) throws -> String? {
        try engine.evaluate(expression, after: scripts, strings: strings, functions: functions)
    }

    @Test func `should run the expression after the scripts, with the texts and functions it is given`() throws {
        let value = try run("greet(name) + ' ' + twice('21')",
                            after: ["function greet(name) { return 'hi ' + name; }"],
                            strings: ["name": "Ada"],
                            functions: ["twice": { Double($0).map { $0 * 2 } }])
        #expect(value == "hi Ada 42")
    }

    @Test func `should keep a text's every character, whatever its script`() throws {
        #expect(try run("text.length + ':' + text", strings: ["text": "한국 ✓"]) == "4:한국 ✓")
    }

    @Test func `should hand a script null when a function has no answer`() throws {
        #expect(try run("String(nothing('x') === null)", functions: ["nothing": { _ in nil }]) == "true")
    }

    @Test func `should answer nothing when the expression is undefined`() throws {
        #expect(try run("undefined") == nil)
    }

    @Test func `should say a script failed to load, with what it threw`() {
        #expect(throws: ScriptEngineError.load("Error: broken")) {
            try run("1", after: ["throw new Error('broken')"])
        }
    }

    @Test func `should say the expression failed, with what it threw`() {
        #expect(throws: ScriptEngineError.run("TypeError: no shape")) {
            try run("read()", after: ["function read() { throw new TypeError('no shape'); }"])
        }
    }

    @Test func `should start each run from a fresh context`() throws {
        _ = try run("leak = 1")
        #expect(try run("typeof leak") == "undefined")
    }

    @Test func `should fail a runaway recursion instead of the process`() {
        #expect {
            try run("deeper()", after: ["function deeper() { return deeper() + 1; }"])
        } throws: { error in
            guard case ScriptEngineError.run = error else { return false }
            return true
        }
    }

    /// The forms the built-in scripts parse, as JavaScriptCore read them:
    /// fractions past milliseconds are cut, an offset may lose its colon, and
    /// a bare date is UTC midnight.
    @Test(arguments: [
        ("2026-03-01T10:00:00Z", 1_772_359_200_000.0),
        ("2026-03-01T10:00:00.123Z", 1_772_359_200_123),
        ("2026-03-01T10:00:00.123456Z", 1_772_359_200_123),
        ("2026-03-01T10:00:00+09:00", 1_772_326_800_000),
        ("2026-03-01T10:00:00+0900", 1_772_326_800_000),
        ("2026-03-01T10:00:00.5+09:00", 1_772_326_800_500),
        ("2026-03-01", 1_772_323_200_000),
    ])
    func `should read the ISO 8601 times the scripts read`(_ text: String, _ milliseconds: Double) throws {
        #expect(try run("String(Date.parse(text))", strings: ["text": text]) == String(Int(milliseconds)))
    }
}
