import Quotas
import Foundation
import Testing
@testable import DataSources

/// A CLI that isn't on this Mac is `cliNotFound` — the fact that lets a login
/// read as *not set up* rather than failing (#198) — not the terminal
/// runner's own error, which reached the popover as "Couldn't connect".
@Suite
struct CLIMissingTests {
    @Test
    func `the terminal runner's missing binary is cliNotFound`() async throws {
        let executor = DefaultCLIExecutor()

        await #expect(throws: UsageError.cliNotFound("claudebar-no-such-cli")) {
            _ = try await executor.execute(binary: "claudebar-no-such-cli", args: [], input: nil, timeout: 1,
                                           workingDirectory: nil, autoResponses: [:])
        }
    }
}
