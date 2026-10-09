import Testing
@testable import DataSources

/// A definition's wildcard picks the same names on the Mac and Windows: it
/// matches as the Mac's `fnmatch` does with no flags (MODULAR_DESIGN §10).
/// Every expectation here is what `fnmatch` answers, except POSIX classes,
/// which match nothing on purpose.
@Suite
struct WildcardTests {
    @Test(arguments: [
        ("rollout-*.jsonl", "rollout-2026-10-08.jsonl", true),
        ("rollout-*.jsonl", "rollout-2026-10-08.json", false),
        ("session_*", "session_", true),
        ("*", "", true),
        ("a*b*c", "axxbyyc", true),
        ("a*b*c", "axxbyy", false),
        ("*ab", "aab", true),
        ("**.db", "state.db", true),
    ])
    func `should let a star stand for any run of characters, even none`(_ pattern: String, _ text: String, _ matches: Bool) {
        #expect(Wildcard.matches(pattern, text) == matches)
    }

    @Test(arguments: [
        ("?.db", "a.db", true),
        ("?.db", ".db", false),
        ("??", "a", false),
        ("state.?db", "state.vdb", true),
    ])
    func `should let a question mark stand for exactly one character`(_ pattern: String, _ text: String, _ matches: Bool) {
        #expect(Wildcard.matches(pattern, text) == matches)
    }

    @Test(arguments: [
        (#"\*.log"#, "*.log", true),
        (#"\*.log"#, "a.log", false),
        (#"a\?"#, "a?", true),
        (#"a\?"#, "ab", false),
    ])
    func `should match an escaped character as itself`(_ pattern: String, _ text: String, _ matches: Bool) {
        #expect(Wildcard.matches(pattern, text) == matches)
    }

    @Test(arguments: [
        ("[abc].txt", "b.txt", true),
        ("[abc].txt", "d.txt", false),
        ("v[0-9]", "v7", true),
        ("v[0-9]", "vx", false),
        ("[!a-c]", "d", true),
        ("[!a-c]", "b", false),
        ("[^a-c]", "d", true),
        ("[]a]", "]", true),
        ("[!]]", "]", false),
        ("[a-]", "-", true),
        (#"[\]]"#, "]", true),
        (#"[\!a]"#, "!", true),
    ])
    func `should match one character of a set, a range or its negation`(_ pattern: String, _ text: String, _ matches: Bool) {
        #expect(Wildcard.matches(pattern, text) == matches)
    }

    @Test(arguments: [
        ("[abc", "a"),
        ("a[", "a["),
        ("*[", "x["),
    ])
    func `should match nothing when a set never closes`(_ pattern: String, _ text: String) {
        #expect(Wildcard.matches(pattern, text) == false)
    }

    @Test(arguments: [
        ("[[:alpha:]]", "a"),
        ("[[:alpha:]]", ":"),
        ("[[.a.]]", "a"),
        ("[[=a=]]", "a"),
    ])
    func `should match nothing rather than misread a POSIX class as a set of characters`(_ pattern: String, _ text: String) {
        #expect(Wildcard.matches(pattern, text) == false)
    }
}
