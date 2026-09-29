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

    @Test
    func `output without a placeholder is never pending`() {
        let costPanelOnly = """
        Opus 5 (1M context) · API Usage Billing
          Session
            Total cost:            $0.0000
        """
        #expect(!CLICompletionRule.claudeUsage.isPending(costPanelOnly))
    }

    /// #317: the screen the CLI shows while still booting carries no ready marker
    /// at all, so a capture that stops there has nothing to parse.
    @Test
    func `the boot screen from issue 317 is still pending`() {
        #expect(CLICompletionRule.claudeUsage.isPending(Self.bootScreen))
    }

    @Test
    func `a settled error ends the wait instead of stalling until the timeout`() {
        let rateLimited = Self.loadingScreen + "\nError: Usage endpoint is rate limited. Please try again in a moment."
        #expect(!CLICompletionRule.claudeUsage.isPending(rateLimited))
    }

    @Test
    func `markers match regardless of case`() {
        let rule = CLICompletionRule(pendingMarkers: ["loading"], readyMarkers: ["done"])
        #expect(rule.isPending("LOADING…"))
        #expect(!rule.isPending("LOADING… DONE"))
    }
}
