#if os(macOS)
import Testing
import Foundation
@testable import DataSources

/// Ending a child a fetch started has a bound (#550): a refresh's deadline
/// closes the CLI it started, and a child still there after `SIGKILL` used to
/// hold that close, the refresh, and every later one, on "Syncing..." forever.
@Suite(.timeLimit(.minutes(1)))
struct ChildTeardownTests {
    /// A child that is asked, then made, to stop, and never does.
    private final class StuckChild: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var signals: [String] { lock.lock(); defer { lock.unlock() }; return asked }
        func record(_ signal: String) { lock.lock(); asked.append(signal); lock.unlock() }
    }

    @Test func `should give up on a child that outlives SIGKILL, after asking and then making it stop`() {
        let child = StuckChild()
        let started = Date()

        let ended = ChildTeardown.end(
            isRunning: { true },
            terminate: { child.record("TERM") },
            kill: { child.record("KILL") },
            grace: 0.2,
            afterKill: 0.2
        )

        #expect(!ended)
        #expect(child.signals == ["TERM", "KILL"])
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func `should end a real child that ignores the request to stop`() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; while :; do sleep 1; done"]
        try process.run()
        // Let the shell install its trap before it is asked to stop.
        Thread.sleep(forTimeInterval: 0.3)

        #expect(ChildTeardown.end(process, named: "test child", grace: 0.2))
        #expect(!process.isRunning)
    }

    @Test func `should not signal a child that has already exited`() {
        let child = StuckChild()

        let ended = ChildTeardown.end(
            isRunning: { false },
            terminate: { child.record("TERM") },
            kill: { child.record("KILL") },
            grace: 0.2,
            afterKill: 0.2
        )

        #expect(ended)
        #expect(child.signals.isEmpty)
    }
}
#endif
