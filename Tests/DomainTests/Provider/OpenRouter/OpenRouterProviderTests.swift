import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("OpenRouterProvider Tests")
@MainActor
struct OpenRouterProviderTests {

    // MARK: - Helper

    private func makeSettings(enabled: Bool = false) -> UserDefaultsProviderSettingsRepository {
        let suiteName = "com.claudebar.test.OpenRouterProvider.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let repo = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        repo.setEnabled(enabled, forProvider: "openrouter")
        return repo
    }

    private func makeSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            providerId: "openrouter",
            quotas: [
                UsageQuota(
                    percentRemaining: 100,
                    quotaType: .modelSpecific("Credits"),
                    providerId: "openrouter",
                    dollarRemaining: Decimal(string: "7.00"),
                    currency: "USD"
                )
            ],
            capturedAt: Date()
        )
    }

    // MARK: - Identity Tests

    @Test
    func `openrouter provider has correct id`() {
        let provider = OpenRouterProvider(probe: MockUsageProbe(), settingsRepository: makeSettings())

        #expect(provider.id == "openrouter")
    }

    @Test
    func `openrouter provider has correct name`() {
        let provider = OpenRouterProvider(probe: MockUsageProbe(), settingsRepository: makeSettings())

        #expect(provider.name == "OpenRouter")
    }

    @Test
    func `openrouter provider is API-only with no cli command`() {
        let provider = OpenRouterProvider(probe: MockUsageProbe(), settingsRepository: makeSettings())

        #expect(provider.cliCommand == "")
    }

    @Test
    func `openrouter provider has dashboard URL pointing to openrouter ai`() {
        let provider = OpenRouterProvider(probe: MockUsageProbe(), settingsRepository: makeSettings())

        #expect(provider.dashboardURL != nil)
        #expect(provider.dashboardURL?.host?.contains("openrouter.ai") == true)
    }

    // MARK: - Enabled State Tests

    @Test
    func `openrouter provider is disabled by default`() {
        // Given: fresh settings with no stored preference
        let settings = makeSettings(enabled: false)
        let provider = OpenRouterProvider(probe: MockUsageProbe(), settingsRepository: settings)

        // Then: requires an API key, so it opts in
        #expect(provider.isEnabled == false)
    }

    @Test
    func `openrouter provider reads enabled state from settings`() {
        let settings = makeSettings(enabled: true)
        let provider = OpenRouterProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(provider.isEnabled == true)
    }

    @Test
    func `openrouter provider persists enabled changes to settings`() {
        let settings = makeSettings(enabled: false)
        let provider = OpenRouterProvider(probe: MockUsageProbe(), settingsRepository: settings)

        provider.isEnabled = true

        #expect(provider.isEnabled == true)
        #expect(settings.isEnabled(forProvider: "openrouter") == true)
    }

    // MARK: - State Tests

    @Test
    func `openrouter provider starts with no snapshot`() {
        let provider = OpenRouterProvider(probe: MockUsageProbe(), settingsRepository: makeSettings())

        #expect(provider.snapshot == nil)
    }

    @Test
    func `openrouter provider starts not syncing`() {
        let provider = OpenRouterProvider(probe: MockUsageProbe(), settingsRepository: makeSettings())

        #expect(provider.isSyncing == false)
    }

    @Test
    func `openrouter provider starts with no error`() {
        let provider = OpenRouterProvider(probe: MockUsageProbe(), settingsRepository: makeSettings())

        #expect(provider.lastError == nil)
    }

    // MARK: - Delegation Tests

    @Test
    func `openrouter provider delegates isAvailable to probe`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let provider = OpenRouterProvider(probe: mockProbe, settingsRepository: makeSettings())

        let isAvailable = await provider.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `openrouter provider delegates isAvailable false to probe`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(false)
        let provider = OpenRouterProvider(probe: mockProbe, settingsRepository: makeSettings())

        let isAvailable = await provider.isAvailable()

        #expect(isAvailable == false)
    }

    // MARK: - Refresh Tests

    @Test
    func `openrouter provider stores snapshot after refresh`() async throws {
        let expectedSnapshot = makeSnapshot()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let provider = OpenRouterProvider(probe: mockProbe, settingsRepository: makeSettings())

        let snapshot = try await provider.refresh()

        #expect(snapshot.providerId == "openrouter")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.dollarRemaining == Decimal(string: "7.00"))
        #expect(provider.snapshot != nil)
        #expect(provider.snapshot?.quotas.first?.dollarRemaining == Decimal(string: "7.00"))
        #expect(provider.lastError == nil)
    }

    @Test
    func `openrouter provider stores error on refresh failure`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let provider = OpenRouterProvider(probe: mockProbe, settingsRepository: makeSettings())

        #expect(provider.lastError == nil)

        do {
            _ = try await provider.refresh()
        } catch {
            // Expected
        }

        #expect(provider.lastError != nil)
    }

    @Test
    func `openrouter provider rethrows probe errors`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let provider = OpenRouterProvider(probe: mockProbe, settingsRepository: makeSettings())

        await #expect(throws: ProbeError.authenticationRequired) {
            try await provider.refresh()
        }
    }

    @Test
    func `openrouter provider clears error on successful refresh`() async throws {
        let settings = makeSettings()

        let failingProbe = MockUsageProbe()
        given(failingProbe).probe().willThrow(ProbeError.authenticationRequired)
        let failingProvider = OpenRouterProvider(probe: failingProbe, settingsRepository: settings)
        do {
            _ = try await failingProvider.refresh()
        } catch {
            // Expected
        }
        #expect(failingProvider.lastError != nil)

        let succeedingProbe = MockUsageProbe()
        given(succeedingProbe).probe().willReturn(makeSnapshot())
        let succeedingProvider = OpenRouterProvider(probe: succeedingProbe, settingsRepository: settings)
        _ = try await succeedingProvider.refresh()

        #expect(succeedingProvider.lastError == nil)
    }

    // MARK: - Syncing State Tests

    @Test
    func `openrouter provider resets isSyncing after refresh completes`() async throws {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(makeSnapshot())
        let provider = OpenRouterProvider(probe: mockProbe, settingsRepository: makeSettings())

        #expect(provider.isSyncing == false)

        _ = try await provider.refresh()

        #expect(provider.isSyncing == false)
    }

    @Test
    func `openrouter provider resets isSyncing after refresh fails`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let provider = OpenRouterProvider(probe: mockProbe, settingsRepository: makeSettings())

        do {
            _ = try await provider.refresh()
        } catch {
            // Expected
        }

        #expect(provider.isSyncing == false)
    }

    // MARK: - Uniqueness Tests

    @Test
    func `openrouter provider has unique id compared to other providers`() {
        let settings = makeSettings()
        let mockProbe = MockUsageProbe()
        let openrouter = OpenRouterProvider(probe: mockProbe, settingsRepository: settings)
        let deepseek = DeepSeekProvider(probe: mockProbe, settingsRepository: settings)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        let ids = Set([openrouter.id, deepseek.id, zai.id, claude.id])
        #expect(ids.count == 4) // All unique
    }
}
