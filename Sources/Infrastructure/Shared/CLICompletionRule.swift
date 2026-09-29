import Foundation

/// Tells a PTY run when a TUI screen is actually finished.
///
/// Going idle is not proof that a screen is done, because a `/usage` capture is a
/// wait for a *target* screen that can be preceded by a long stretch of quiet.
/// The CLI only submits `/usage` once it has finished booting — its SessionStart
/// hooks first, on a busy machine for seconds — and then fills the quota bars in
/// from a second request a few seconds after the Usage tab opens. Every one of
/// those screens is "not finished", and a capture that stops on one holds nothing
/// to parse (#271, #317).
///
/// Readiness is therefore decided positively: a screen is finished when it
/// carries a marker that only a settled screen has, whether that is the data we
/// asked for or the error that replaced it. A screen that carries no such marker
/// is still filling in, whether or not it happens to be painting a placeholder.
/// The PTY buffer is cumulative — a redraw appends, it does not erase — so a
/// placeholder appearing or disappearing proves nothing either way.
public struct CLICompletionRule: Sendable, Equatable {
    /// Markers whose presence means the screen has settled, data or error.
    public let readyMarkers: [String]

    public init(readyMarkers: [String]) {
        self.readyMarkers = readyMarkers
    }

    /// True while the captured screen has not shown a ready marker yet.
    public func isPending(_ text: String) -> Bool {
        !isReady(text)
    }

    /// True once the screen carries a ready marker.
    public func isReady(_ text: String) -> Bool {
        let screen = Self.searchableText(text)
        return readyMarkers.contains { screen.contains(Self.searchableText($0)) }
    }

    /// The text a marker is actually findable in.
    ///
    /// A TUI redraw writes every word run at its own absolute column, so
    /// `Current session` reaches the PTY as `Curre␛[10Gt␛[12Gsession` and
    /// `38% used` as `38%␛[59Gused`: the words are split by escape sequences,
    /// and the visible gap between them is padding the terminal would have
    /// inserted, not bytes the CLI sent. Searching the raw capture for a phrase
    /// therefore finds nothing — neither the ready markers nor, as it turns out,
    /// the "Loading usage data" placeholder that #271 added. Dropping the
    /// escapes and comparing with whitespace removed is what the rendered screen
    /// actually says, and costs one pass over a buffer that tops out at a few
    /// tens of KB.
    private static func searchableText(_ text: String) -> String {
        let withoutEscapes = escapeSequence?
            .stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            ) ?? text
        return withoutEscapes
            .lowercased()
            .filter { !$0.isWhitespace }
    }

    /// OSC (…BEL / …ST), CSI (`␛[` + parameters + a final byte), charset
    /// designators, and the two-character escapes Claude Code uses for save and
    /// restore (`␛7`, `␛8`).
    private static let escapeSequence: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)|\x1B\[[0-9;?]*[A-Za-z]|\x1B[()][AB012]|\x1B[78]"#
        )
    }()

    /// The rule for `claude /usage`.
    ///
    /// Ready markers cover both outcomes so a stalled or rate-limited endpoint
    /// ends the wait as soon as the CLI says so, instead of holding the run open
    /// until the probe timeout.
    public static let claudeUsage = CLICompletionRule(
        readyMarkers: [
            "Current session",
            "% used",
            "% left",
            "rate limited",
            "Error:",
            "/usage is only available",
        ]
    )
}
