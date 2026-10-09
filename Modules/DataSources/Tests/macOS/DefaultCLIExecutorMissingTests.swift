#if os(macOS)
import Quotas
import Foundation
import Testing
@testable import DataSources

/// The Mac's terminal runner says a CLI it can't find is `cliNotFound` (#198).
@Suite
struct DefaultCLIExecutorMissingTests {
    @Test
    func `should report the CLI as not found when it isn't on this Mac`() async throws {
        let executor = DefaultCLIExecutor()

        await #expect(throws: UsageError.cliNotFound("claudebar-no-such-cli")) {
            _ = try await executor.execute(binary: "claudebar-no-such-cli", args: [], input: nil, timeout: 1,
                                           workingDirectory: nil, autoResponses: [:])
        }
    }
}
#endif
