import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// Issue #210: the Claude CLI binary is user-configurable for setups where
/// the real binary is not the `claude` on PATH (an aliased name, a wrapper
/// install, a versioned binary). These tests pin the wiring contract: whatever
/// `ClaudeSettingsRepository.resolvedClaudeBinary()` resolves is the binary the
/// probes locate and execute — exactly the way `ClaudeBarApp` constructs them.
///
/// Shell aliases and functions are deliberately unsupported: a subprocess can
/// only exec a binary path or a PATH-resolvable name, never a shell command
/// line (no `sh -c`).
@Suite
struct ClaudeBinarySettingTests {

    private let testSuiteName = "com.claudebar.test.claudebinary.\(UUID().uuidString)"

    private func makeRepository() -> UserDefaultsProviderSettingsRepository {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        return UserDefaultsProviderSettingsRepository(userDefaults: defaults)
    }

    private func cleanupDefaults() {
        UserDefaults().removePersistentDomain(forName: testSuiteName)
    }

    private static let usageOutput = """
    Opus 4.5 · Claude Max · user@example.com's Organization

    Current session
    ████████████████░░░░ 65% left
    Resets in 2h 15m

    Current week (all models)
    ██████████░░░░░░░░░░ 35% left
    Resets Dec 28
    """

    private static let passOutput = """
    > /passes
      ⎿  Referral link copied to clipboard!
    """

    // MARK: - ClaudeUsageProbe

    @Test
    func `unset setting probes with the default claude binary`() async {
        // Given — no binary configured; the wiring must fall back to "claude"
        let repository = makeRepository()
        defer { cleanupDefaults() }

        let mockExecutor = MockCLIExecutor()
        // Only matches when the probe locates the default binary.
        given(mockExecutor).locate(.value("claude")).willReturn("/usr/local/bin/claude")

        let probe = ClaudeUsageProbe(
            claudeBinary: repository.resolvedClaudeBinary(),
            cliExecutor: mockExecutor
        )

        // Then — available proves the locate ran for "claude", not another name
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `configured binary reaches the usage probe execute call`() async throws {
        // Given — a non-standard binary persisted in settings
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.setClaudeBinary("/opt/tools/bin/claude-work")

        let mockExecutor = MockCLIExecutor()
        // Only matches when the probe executes the configured binary.
        given(mockExecutor).execute(
            binary: .value("/opt/tools/bin/claude-work"),
            args: .matching { $0.first == "/usage" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.usageOutput, exitCode: 0))

        let accountInfo = MockAccountInfoResolving()
        given(accountInfo).resolve().willReturn(nil)

        let probe = ClaudeUsageProbe(
            claudeBinary: repository.resolvedClaudeBinary(),
            cliExecutor: mockExecutor,
            accountInfoResolver: accountInfo
        )

        // When — parsed quota data can only come from the stub above, so a
        // successful probe proves the configured binary was executed
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.accountTier == .claudeMax)
        #expect(snapshot.quotas.count >= 1)
    }

    @Test
    func `empty setting falls back to the default claude binary in the usage probe`() async {
        // Given — the user cleared the field
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.setClaudeBinary("   ")

        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.value("claude")).willReturn("/usr/local/bin/claude")

        let probe = ClaudeUsageProbe(
            claudeBinary: repository.resolvedClaudeBinary(),
            cliExecutor: mockExecutor
        )

        #expect(await probe.isAvailable() == true)
    }

    // MARK: - ClaudePassProbe

    @Test
    func `unset setting probes passes with the default claude binary`() async {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.value("claude")).willReturn("/usr/local/bin/claude")

        let probe = ClaudePassProbe(
            claudeBinary: repository.resolvedClaudeBinary(),
            cliExecutor: mockExecutor
        )

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `configured binary reaches the pass probe execute call`() async throws {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.setClaudeBinary("/opt/tools/bin/claude-work")

        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).execute(
            binary: .value("/opt/tools/bin/claude-work"),
            args: .matching { $0.first == "/passes" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.passOutput, exitCode: 0))

        let clipboard = MockClipboardReader(content: "https://claude.ai/referral/TEST123")

        let probe = ClaudePassProbe(
            claudeBinary: repository.resolvedClaudeBinary(),
            cliExecutor: mockExecutor,
            clipboardReader: clipboard
        )

        // The referral URL only comes from the stubbed run of the configured
        // binary, so a returned pass proves that binary was executed
        let pass = try await probe.probe()

        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/TEST123")
    }

    @Test
    func `empty setting falls back to the default claude binary in the pass probe`() async {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.setClaudeBinary("")

        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.value("claude")).willReturn("/usr/local/bin/claude")

        let probe = ClaudePassProbe(
            claudeBinary: repository.resolvedClaudeBinary(),
            cliExecutor: mockExecutor
        )

        #expect(await probe.isAvailable() == true)
    }
}
