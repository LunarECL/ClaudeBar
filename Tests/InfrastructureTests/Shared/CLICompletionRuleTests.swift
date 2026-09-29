import Testing
import Foundation
@testable import Infrastructure

@Suite
struct CLICompletionRuleTests {

    /// What `claude /usage` paints within milliseconds of opening the Usage tab —
    /// the cost panel plus a placeholder, before the quota request comes back.
    static let loadingScreen = """
    Claude Code v2.1.251
    Opus 5 (1M context) · Claude Max

      Settings  Status  Config  Usage  Stats

      Session
        Total cost:            $0.0000
        Total duration (API):  0s
        Usage:                 0 input, 0 output, 0 cache read, 0 cache write

        Loading usage data…

      Esc to cancel
    """

    /// The same capture a few seconds later. The PTY buffer is cumulative, so the
    /// placeholder is still in the text — readiness comes from the quota bars.
    static let loadedScreen = loadingScreen + """

      Current session
        ▌                       1% used
        Resets 3:20pm (Asia/Shanghai)
    """

    /// The screen `claude` shows while it is still booting: `/usage` is sitting
    /// unsubmitted in the input box and the SessionStart hooks are still running,
    /// so the Usage tab has not opened at all.
    ///
    /// Verbatim from the `ClaudeBar.log` attached to issue #317 — the capture that
    /// logged at `2026-09-23T18:14:45Z`, trimmed to the first frames (the rest was
    /// the hook's own output). The cursor escapes are kept because they are the
    /// point: the CLI writes every word run at its own absolute column, so no
    /// phrase on this screen reaches the PTY contiguously.
    static let bootScreen = """
    \u{1B}[1C\u{1B}[1B▐▛███▛█\u{1B}[12GClaude\u{1B}[19GCode\u{1B}[24Gv2.1.273
    \u{1B}[1B▝▜██████▀\u{1B}[12GOpus\u{1B}[17G5\u{1B}[19G(1M\u{1B}[23Gcontext)\u{1B}[32Gwith\u{1B}[37Ghigh\u{1B}[42Geffort\u{1B}[49G·\u{1B}[51GAPI\u{1B}[55GUsage\u{1B}[61GBilling
    \u{1B}[2C\u{1B}[1B▝▝\u{1B}[6G▝▝\u{1B}[12G~/Library/Application\u{1B}[34GSupport/ClaudeBar/Probe
    \u{1B}[3B❯\u{1B}[3G/usage
    \u{1B}[38B✢\u{1B}[3GBurrowing…\u{1B}[14G(running\u{1B}[23GSessionStart\u{1B}[36Ghooks…\u{1B}[43G2/5\u{1B}[47G·\u{1B}[49G0s)
    \u{1B}[142C\u{1B}[1B●\u{1B}[145Ghigh\u{1B}[150G·\u{1B}[152G/effort
    \u{1B}[2C\u{1B}[1B⏵⏵\u{1B}[6Gauto\u{1B}[11Gmode\u{1B}[16Gon\u{1B}[19G(shift+tab\u{1B}[30Gto\u{1B}[33Gcycle)\u{1B}[40G·\u{1B}[42Gesc\u{1B}[46Gto\u{1B}[49Ginterrupt\u{1B}[59G·\u{1B}[61G←\u{1B}[63Gfor\u{1B}[67Gagents
    \u{1B}[2C\u{1B}[1B Settings  Status   Config   Usage   Stats
    \u{1B}[2B Session
    \u{1B} Total cost:            $0.0000
    \u{1B} Total duration (API):  0s
    \u{1B} Total duration (wall): 1s
    \u{1B} Total code changes:  0 lines added, 0 lines removed
    \u{1B} Usage: 0 input, 0 output, 0 cache read, 0 cache write
    \u{1B} Esc\u{1B}[8Gto\u{1B}[11Gcancel
    """

    @Test
    func `output is pending while the placeholder is the only thing rendered`() {
        #expect(CLICompletionRule.claudeUsage.isPending(Self.loadingScreen))
    }

    @Test
    func `output is ready once quota bars arrive even though the placeholder remains`() {
        #expect(!CLICompletionRule.claudeUsage.isPending(Self.loadedScreen))
    }

    /// #317 changed this invariant, and the old name said what it claimed:
    /// "no placeholder" was treated as "settled". The placeholder is only one way
    /// a `/usage` capture can be unfinished — a CLI that has not opened the Usage
    /// tab yet is equally unfinished, and accepting that screen handed the parser
    /// captures with nothing in them. Readiness is now positive evidence: a ready
    /// marker on screen, and without one the capture is still filling in.
    @Test
    func `output that never reached the Usage tab is pending even without a placeholder`() {
        let costPanelOnly = """
        Opus 5 (1M context) · API Usage Billing
          Session
            Total cost:            $0.0000
        """
        #expect(CLICompletionRule.claudeUsage.isPending(costPanelOnly))
    }

    /// #317: the screen the CLI shows while still booting carries no ready marker
    /// at all, so a capture that stops there has nothing to parse.
    @Test
    func `the boot screen from issue 317 is still pending`() {
        #expect(CLICompletionRule.claudeUsage.isPending(Self.bootScreen))
    }

    /// A TUI redraw writes every word run at its own absolute column, so
    /// `Current session` reaches the PTY as `Curre␛[10Gt␛[12Gsession` and
    /// `38% used` as `38%␛[59Gused`. Searching the raw bytes for a ready marker
    /// never finds them, which would hold the capture open on a screen that is
    /// already finished.
    @Test
    func `a ready marker split across cursor positions still ends the wait`() {
        let split = """
        \u{1B}[3C\u{1B}[2BCurre\u{1B}[10Gt\u{1B}[12Gsession
        \u{1B}[1B█████\u{1B}[55G38%\u{1B}[59Gused
        """
        #expect(!CLICompletionRule.claudeUsage.isPending(split))
    }

    /// The same placeholder, cursor-split the way the CLI really writes it. This
    /// is why the "Loading usage data" marker #271 added never once matched a
    /// real screen in the 430 captures attached to #317.
    @Test
    func `a cursor-split placeholder is still pending`() {
        let split = "\u{1B}[3C\u{1B}[2BLoading\u{1B}[12Gusage\u{1B}[18Gdata…"
        #expect(CLICompletionRule.claudeUsage.isPending(split))
    }

    @Test
    func `a settled error ends the wait instead of stalling until the timeout`() {
        let rateLimited = Self.loadingScreen + "\nError: Usage endpoint is rate limited. Please try again in a moment."
        #expect(!CLICompletionRule.claudeUsage.isPending(rateLimited))
    }

    /// The screen `claude /cost` settles on, and why it carries no `/usage` rule.
    ///
    /// `/cost` is one static panel written in a single pass, so it has no
    /// "still filling in" phase and needs no rule: the probe runs it with
    /// `completionRule: nil` and the ordinary idle cutoff ends the capture. What
    /// this pins down is that the `/usage` rule must not be borrowed for it —
    /// a settled `/cost` screen has no quota bars, so it matches none of that
    /// rule's markers and `isPending` would never fall, costing every run the
    /// full 20s timeout (#317).
    static let settledCostScreen = """
    Claude Code v2.1.273
      Session
        Total cost:            $3.5500
        Total duration (API):  6m 19.7s
        Total duration (wall): 6h 33m 10.2s
        Total code changes:    12 lines added, 3 lines removed
      Esc to cancel
    """

    @Test
    func `a settled cost screen matches none of the usage ready markers`() {
        // This is the reason `/cost` runs under no rule at all rather than this
        // one: borrowed as-is, the rule can never say "done" here, and the run
        // waits out the full timeout before the parser sees a finished screen.
        #expect(CLICompletionRule.claudeUsage.isPending(Self.settledCostScreen))
    }

    /// The CLI paints the cost panel during boot, before `/cost` is submitted —
    /// it is in the boot screen fixture above. So a ready marker keyed on
    /// `Total cost` would fire on a screen where no cost has been read yet and
    /// the probe would answer $0.00. Recorded here so the reason `/cost` takes
    /// no rule is not "revisit this and add a marker" (#317).
    @Test
    func `a total-cost marker would fire on the boot screen before cost is submitted`() {
        #expect(CLICompletionRule.claudeUsage.isPending(Self.bootScreen))
        #expect(Self.bootScreen.contains("Total cost"))
    }

    @Test
    func `a marker matches an uppercase screen and not an uppercase non-match`() {
        let rule = CLICompletionRule(readyMarkers: ["done"])
        #expect(rule.isPending("LOADING…"))
        #expect(!rule.isPending("LOADING… DONE"))
    }
}
