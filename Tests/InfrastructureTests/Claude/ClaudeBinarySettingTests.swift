import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// Issue #210: the Claude CLI binary is user-configurable for setups where
/// the real binary is not the `claude` on PATH (an aliased name, a wrapper
/// install, a versioned binary). These tests pin the wiring contract:
/// whatever `ClaudeSettingsRepository.resolvedClaudeBinary()` resolves is the
/// binary the guest-pass source locates and executes — exactly the way
/// `ClaudeBarApp` constructs it. The definition-driven CLI data sources are
/// pinned on their side by `runningCLI` tests in ProvidersTests
/// (ClaudeCLIDefinitionTests).
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

    private static let passOutput = """
    > /passes
      ⎿  Referral link copied to clipboard!
    """

    // MARK: - The resolver

    @Test
    func `unset setting resolves to the default claude binary`() {
        // Given — nothing configured
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // Then
        #expect(repository.claudeBinary() == "")
        #expect(repository.resolvedClaudeBinary() == "claude")
    }

    @Test
    func `a configured binary is resolved as-is, trimmed`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        repository.setClaudeBinary("  /opt/tools/bin/claude-work \n")

        #expect(repository.resolvedClaudeBinary() == "/opt/tools/bin/claude-work")
    }

    // MARK: - The guest-pass source

    @Test
    func `unset setting locates the default claude binary`() async {
        // Given — no binary configured; the wiring must fall back to "claude"
        let repository = makeRepository()
        defer { cleanupDefaults() }

        let mockExecutor = MockCLIExecutor()
        // Only matches when the source locates the default binary.
        given(mockExecutor).locate(.value("claude")).willReturn("/usr/local/bin/claude")

        let source = ClaudeGuestPassSource(
            claudeBinary: repository.resolvedClaudeBinary(),
            cliExecutor: mockExecutor
        )

        // Then — available proves the locate ran for "claude", not another name
        #expect(await source.isAvailable() == true)
    }

    @Test
    func `configured binary reaches the guest-pass execute call`() async throws {
        // Given — a non-standard binary persisted in settings
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.setClaudeBinary("/opt/tools/bin/claude-work")

        let mockExecutor = MockCLIExecutor()
        // Only matches when the source executes the configured binary.
        given(mockExecutor).execute(
            binary: .value("/opt/tools/bin/claude-work"),
            args: .matching { $0.first == "/passes" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.passOutput, exitCode: 0))

        let clipboard = MockClipboardReader(content: "https://claude.ai/referral/TEST123")

        let source = ClaudeGuestPassSource(
            claudeBinary: repository.resolvedClaudeBinary(),
            cliExecutor: mockExecutor,
            clipboardReader: clipboard
        )

        // The referral URL only comes from the stubbed run of the configured
        // binary, so a returned pass proves that binary was executed
        let pass = try await source.fetch()

        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/TEST123")
    }

    @Test
    func `whitespace setting falls back to the default claude binary`() async {
        // Given — the user cleared the field, leaving blanks
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.setClaudeBinary("   ")

        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.value("claude")).willReturn("/usr/local/bin/claude")

        let source = ClaudeGuestPassSource(
            claudeBinary: repository.resolvedClaudeBinary(),
            cliExecutor: mockExecutor
        )

        #expect(await source.isAvailable() == true)
    }
}
