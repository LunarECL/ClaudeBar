import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("CodexProvider Tests")
@MainActor
struct CodexProviderTests {

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Identity

    @Test
    func `codex provider has correct id`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(codex.id == "codex")
    }

    @Test
    func `codex provider has correct name`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(codex.name == "Codex")
    }

    @Test
    func `codex provider has correct cliCommand`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(codex.cliCommand == "codex")
    }

    @Test
    func `codex provider has dashboard URL pointing to openai`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(codex.dashboardURL != nil)
        #expect(codex.dashboardURL?.host?.contains("openai") == true)
    }

    @Test
    func `codex provider is enabled by default`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(codex.isEnabled == true)
    }
}

// MARK: - Background refresh stays passive until first explicit verification (issue #216)

@Suite("CodexProvider Verified-Session Gating Tests")
@MainActor
struct CodexProviderVerifiedSessionTests {

    /// Hand-written probe double (mirrors CountingUsageProbe in
    /// QuotaMonitorTests): records its calls as state so tests can assert on
    /// the resulting count. Used instead of Mockable's `verify` so the
    /// "probe was NOT called" assertion is a plain expectation.
    private final class CountingProbe: UsageProbe, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        private let snapshot: UsageSnapshot

        init(percent: Int = 50) {
            snapshot = UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: Double(percent), quotaType: .session, providerId: "codex")],
                capturedAt: Date()
            )
        }

        var calls: Int { lock.withLock { _calls } }

        func probe() async throws -> UsageSnapshot {
            lock.withLock { _calls += 1 }
            return snapshot
        }

        func isAvailable() async -> Bool { true }
    }

    private func makeCodexSettings(
        verified: Bool = false,
        mode: CodexProbeMode = .rpc
    ) -> FakeCodexSettings {
        FakeCodexSettings(probeMode: mode, verifiedAtLeastOnce: verified)
    }

    private func makeBaseSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    @Test
    func `background refresh does not probe before an explicit refresh succeeded`() async {
        let settings = makeCodexSettings(verified: false)
        let rpcProbe = CountingProbe()
        let apiProbe = CountingProbe()

        let codex = CodexProvider(rpcProbe: rpcProbe, apiProbe: apiProbe, settingsRepository: settings)

        await #expect(throws: ProbeError.self) {
            try await codex.refresh(.background)
        }

        // The passive path must not touch either probe — no codex subprocess
        #expect(rpcProbe.calls == 0)
        #expect(apiProbe.calls == 0)
        #expect(codex.snapshot == nil)
        #expect(codex.lastError != nil)
    }

    @Test
    func `passive background refresh names the explicit action that checks the session`() async {
        let settings = makeCodexSettings(verified: false)
        let codex = CodexProvider(rpcProbe: CountingProbe(), apiProbe: CountingProbe(), settingsRepository: settings)

        do {
            _ = try await codex.refresh(.background)
        } catch {
            #expect(error.localizedDescription == "Codex CLI session not checked. Click Refresh or Connect to check Codex status.")
        }
    }

    @Test
    func `background refresh keeps the existing snapshot without probing`() async throws {
        // Start in API mode: an interactive refresh seeds a snapshot but does
        // not verify the RPC session (only an RPC probe can).
        let settings = makeCodexSettings(verified: false, mode: .api)
        let rpcProbe = CountingProbe(percent: 70)
        let apiProbe = CountingProbe(percent: 70)
        let codex = CodexProvider(rpcProbe: rpcProbe, apiProbe: apiProbe, settingsRepository: settings)

        _ = try await codex.refresh(.interactive)
        #expect(rpcProbe.calls == 0)

        // Switching to RPC mode arms the gate: the background pass must hand
        // back the existing snapshot instead of spawning the CLI.
        settings.probeMode = .rpc

        let result = try await codex.refresh(.background)
        #expect(result.sessionQuota?.percentRemaining == 70)
        #expect(rpcProbe.calls == 0)
    }

    @Test
    func `interactive refresh marks the session verified for later background refreshes`() async throws {
        let settings = makeCodexSettings(verified: false)
        let rpcProbe = CountingProbe(percent: 50)
        let codex = CodexProvider(rpcProbe: rpcProbe, apiProbe: CountingProbe(), settingsRepository: settings)

        _ = try await codex.refresh(.interactive)
        #expect(settings.verifiedAtLeastOnce == true)

        // The successful explicit refresh lifted the gate: the next background
        // refresh probes again instead of staying passive.
        let result = try await codex.refresh(.background)
        #expect(result.sessionQuota?.percentRemaining == 50)
        #expect(rpcProbe.calls == 2)
    }

    @Test
    func `interactive refresh in API mode does not verify the RPC session`() async throws {
        let settings = makeCodexSettings(verified: false, mode: .api)
        let apiProbe = CountingProbe(percent: 80)
        let rpcProbe = CountingProbe()
        let codex = CodexProvider(rpcProbe: rpcProbe, apiProbe: apiProbe, settingsRepository: settings)

        let result = try await codex.refresh(.interactive)
        #expect(result.sessionQuota?.percentRemaining == 80)
        #expect(apiProbe.calls == 1)
        #expect(settings.verifiedAtLeastOnce == false)

        // Switching to RPC mode arms the gate: the RPC probe never ran, so
        // the background pass stays passive — it hands back the existing
        // snapshot instead of spawning the CLI.
        settings.probeMode = .rpc
        let background = try await codex.refresh(.background)
        #expect(background.sessionQuota?.percentRemaining == 80)
        #expect(rpcProbe.calls == 0)
    }

    @Test
    func `background refresh probes normally once the session is verified`() async throws {
        let settings = makeCodexSettings(verified: true)
        let rpcProbe = CountingProbe(percent: 30)
        let codex = CodexProvider(rpcProbe: rpcProbe, apiProbe: CountingProbe(), settingsRepository: settings)

        let result = try await codex.refresh(.background)
        #expect(result.sessionQuota?.percentRemaining == 30)
        #expect(rpcProbe.calls == 1)
        #expect(codex.lastError == nil)
    }

    @Test
    func `provider without a Codex settings repository stays passive in the background`() async {
        let settings = makeBaseSettingsRepository()
        let probe = CountingProbe()

        let codex = CodexProvider(probe: probe, settingsRepository: settings)

        await #expect(throws: ProbeError.self) {
            try await codex.refresh(.background)
        }
        #expect(probe.calls == 0)
    }
}

// MARK: - Test Helpers

/// Hand-written fake mirroring `FakeClaudeSettings` (ClaudeProviderTests):
/// remembers writes so tests can assert on resulting state.
private final class FakeCodexSettings: CodexSettingsRepository, @unchecked Sendable {
    var probeMode: CodexProbeMode
    var verifiedAtLeastOnce: Bool

    init(probeMode: CodexProbeMode = .rpc, verifiedAtLeastOnce: Bool = false) {
        self.probeMode = probeMode
        self.verifiedAtLeastOnce = verifiedAtLeastOnce
    }

    func isEnabled(forProvider id: String) -> Bool { true }
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { true }
    func setEnabled(_ enabled: Bool, forProvider id: String) {}
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}
    func codexProbeMode() -> CodexProbeMode { probeMode }
    func setCodexProbeMode(_ mode: CodexProbeMode) { probeMode = mode }
    func codexVerifiedAtLeastOnce() -> Bool { verifiedAtLeastOnce }
    func setCodexVerifiedAtLeastOnce(_ verified: Bool) { verifiedAtLeastOnce = verified }
}
