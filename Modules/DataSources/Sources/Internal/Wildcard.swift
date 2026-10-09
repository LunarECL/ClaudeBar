/// A definition's wildcard, matched as the Mac's `fnmatch` does with no flags,
/// so a pattern picks the same files on the Mac and Windows (MODULAR_DESIGN
/// §10). `*` is any run of characters, `?` one character, `\` makes the next
/// character itself, and `[…]` is one of a set: `a-z` a range, `!` or `^`
/// first to negate, `]` first as itself. As in Apple's `fnmatch`, a set reads
/// `\` as an escape only before the character it matches, and a set that never
/// closes fails the whole match. Unlike it, a POSIX class or collating symbol
/// (`[:alpha:]`, `[.a.]`, `[=a=]`) before that character matches nothing.
enum Wildcard {
    static func matches(_ pattern: String, _ text: String) -> Bool {
        let pattern = Array(pattern)
        let text = Array(text)
        var p = 0
        var t = 0
        // The pattern after the last `*`, and where in the text it now starts,
        // so a mismatch can give that `*` one more character.
        var star: (pattern: Int, text: Int)?

        func backtrack() -> Bool {
            guard let last = star, last.text < text.count else { return false }
            star = (last.pattern, last.text + 1)
            p = last.pattern
            t = last.text + 1
            return true
        }

        while true {
            guard p < pattern.count else {
                if t == text.count { return true }
                if backtrack() { continue }
                return false
            }
            let element = pattern[p]
            p += 1
            let character: Character? = t < text.count ? text[t] : nil
            switch element {
            case "?":
                guard character != nil else { return false }
                t += 1
            case "*":
                while p < pattern.count, pattern[p] == "*" { p += 1 }
                if p == pattern.count { return true }
                star = (p, t)
            case "[":
                guard let character else { return false }
                switch set(pattern, from: p, matching: character) {
                case .malformed:
                    return false
                case .match(let end):
                    p = end
                    t += 1
                case .noMatch:
                    if backtrack() { continue }
                    return false
                }
            default:
                var literal = element
                if element == "\\" {
                    guard p < pattern.count else { return false }
                    literal = pattern[p]
                    p += 1
                }
                if let character, character == literal {
                    t += 1
                } else {
                    if backtrack() { continue }
                    return false
                }
            }
        }
    }

    private enum SetMatch {
        case match(end: Int)
        case noMatch
        case malformed
    }

    /// Whether the set whose `[` comes just before `start` holds `character`,
    /// and where the pattern goes on after its `]`.
    private static func set(_ pattern: [Character], from start: Int, matching character: Character) -> SetMatch {
        func isClass(_ index: Int) -> Bool {
            pattern[index] == "[" && index + 1 < pattern.count && [".", "=", ":"].contains(pattern[index + 1])
        }
        var i = start
        let negated = i < pattern.count && (pattern[i] == "!" || pattern[i] == "^")
        if negated { i += 1 }
        let first = i
        var found = false
        while true {
            guard i < pattern.count else { return .malformed }
            if pattern[i] == "]" && i > first { break }
            if isClass(i) { return .malformed }
            if pattern[i] == "\\" {
                i += 1
                guard i < pattern.count else { return .malformed }
            }
            let low = pattern[i]
            i += 1
            if i + 1 < pattern.count, pattern[i] == "-", pattern[i + 1] != "]" {
                i += 1
                if pattern[i] == "\\" { i += 1 }
                guard i < pattern.count else { return .malformed }
                if isClass(i) { return .malformed }
                let high = pattern[i]
                i += 1
                if low <= character && character <= high {
                    found = true
                    break
                }
            } else if low == character {
                found = true
                break
            }
        }
        // The rest of the set is skipped as written: no escapes, and a `[.`,
        // `[=` or `[:` runs to its own closing `.]`, `=]` or `:]`.
        var symbol: Character?
        while i < pattern.count, pattern[i] != "]" {
            if let open = symbol, pattern[i] == open {
                i += 1
                if i < pattern.count, pattern[i] == "]" {
                    symbol = nil
                    i += 1
                }
            } else if symbol == nil, pattern[i] == "[" {
                i += 1
                if i < pattern.count, [".", "=", ":"].contains(pattern[i]) {
                    symbol = pattern[i]
                    i += 1
                }
            } else {
                i += 1
            }
        }
        guard i < pattern.count else { return .malformed }
        return found == negated ? .noMatch : .match(end: i + 1)
    }
}
