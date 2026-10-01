import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Issue #141: the popover pills, the overview and ⌘1–⌘9 must follow the
/// user's persisted provider order instead of the fixed registration order.
@Suite
@MainActor
struct QuotaMonitorProviderOrderTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    /// Settings mock: every provider enabled, persisting the given order.
    private func makeSettingsRepository(order: [String] = []) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        given(mock).providerOrder().willReturn(order)
        given(mock).setProviderOrder(.any).willReturn()
        return mock
    }

    /// Registration order [claude, codex, gemini], as ClaudeBarApp registers them.
    /// Claude and Codex are definition-driven since #329, so these tests use the
    /// shared id/name stubs; only the monitor's ordering matters here.
    private func makeProviders(settings: any ProviderSettingsRepository) -> AIProviders {
        AIProviders(providers: [
            StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings),
            StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings),
            GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings),
        ])
    }

    private func makeMonitor(
        providers: AIProviders,
        settings: (any ProviderSettingsRepository)? = nil
    ) -> QuotaMonitor {
        QuotaMonitor(
            providers: providers,
            alerter: nil,
            clock: TestClock(),
            settingsRepository: settings
        )
    }

    // MARK: - Reading the persisted order

    @Test
    func `no persisted order keeps registration order`() {
        let settings = makeSettingsRepository(order: [])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.enabledProviders.map(\.id) == ["claude", "codex", "gemini"])
        #expect(monitor.allProviders.map(\.id) == ["claude", "codex", "gemini"])
    }

    @Test
    func `enabledProviders follow the persisted order`() {
        let settings = makeSettingsRepository(order: ["gemini", "claude", "codex"])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.enabledProviders.map(\.id) == ["gemini", "claude", "codex"])
    }

    @Test
    func `allProviders follow the persisted order`() {
        let settings = makeSettingsRepository(order: ["gemini", "claude", "codex"])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.allProviders.map(\.id) == ["gemini", "claude", "codex"])
    }

    @Test
    func `stored order omitting a provider falls back to its registration position`() {
        // "gone" was removed from the app; claude and codex are not listed, so
        // they keep their registration order behind the listed gemini.
        let settings = makeSettingsRepository(order: ["gemini", "gone"])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.allProviders.map(\.id) == ["gemini", "claude", "codex"])
    }

    @Test
    func `stored id whose provider is disabled is skipped in enabledProviders`() {
        let settings = makeSettingsRepository(order: ["gemini", "claude", "codex"])
        let repository = makeProviders(settings: settings)
        repository.provider(id: "codex")?.isEnabled = false
        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.enabledProviders.map(\.id) == ["gemini", "claude"])
        // ... while allProviders still shows the full persisted order
        #expect(monitor.allProviders.map(\.id) == ["gemini", "claude", "codex"])
    }

    // MARK: - Keyboard selection follows the persisted order

    @Test
    func `selectProvider atPosition follows the persisted order`() {
        let settings = makeSettingsRepository(order: ["gemini", "claude", "codex"])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        monitor.selectProvider(atPosition: 1)
        #expect(monitor.selectedProviderId == "gemini")

        monitor.selectProvider(atPosition: 2)
        #expect(monitor.selectedProviderId == "claude")

        monitor.selectProvider(atPosition: 3)
        #expect(monitor.selectedProviderId == "codex")
    }

    @Test
    func `selectProvider atPosition skips disabled providers`() {
        let settings = makeSettingsRepository(order: ["gemini", "claude", "codex"])
        let repository = makeProviders(settings: settings)
        repository.provider(id: "gemini")?.isEnabled = false
        let monitor = makeMonitor(providers: repository, settings: settings)

        // ⌘1 lands on the first *enabled* provider in the persisted order.
        monitor.selectProvider(atPosition: 1)
        #expect(monitor.selectedProviderId == "claude")
    }

    // MARK: - Reordering

    @Test
    func `moveProvider reorders and persists the new order`() {
        let settings = makeSettingsRepository(order: [])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        monitor.moveProvider(id: "gemini", by: -2)

        #expect(monitor.allProviders.map(\.id) == ["gemini", "claude", "codex"])
        #expect(monitor.enabledProviders.map(\.id) == ["gemini", "claude", "codex"])
    }

    @Test
    func `moveProvider clamps at the boundaries`() {
        let settings = makeSettingsRepository(order: [])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        monitor.moveProvider(id: "claude", by: -1)
        #expect(monitor.allProviders.map(\.id) == ["claude", "codex", "gemini"])

        monitor.moveProvider(id: "gemini", by: 5)
        #expect(monitor.allProviders.map(\.id) == ["claude", "codex", "gemini"])
    }

    @Test
    func `moveProvider works without a settings repository`() {
        let repository = makeProviders(settings: makeSettingsRepository())
        let monitor = makeMonitor(providers: repository, settings: nil)

        monitor.moveProvider(id: "codex", by: -1)
        #expect(monitor.allProviders.map(\.id) == ["codex", "claude", "gemini"])
    }

    @Test
    func `monitor loads the persisted order at init`() {
        let settings = makeSettingsRepository(order: ["codex", "gemini", "claude"])
        let repository = makeProviders(settings: settings)

        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.allProviders.map(\.id) == ["codex", "gemini", "claude"])
    }
}
