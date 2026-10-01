import Testing
import Foundation
import Mockable
@testable import Domain

@Suite
@MainActor
struct ClaudeProviderDashboardTests {

    private static let subscriptionUsageURL = URL(string: "https://claude.ai/new#settings/usage")
    private static let consoleBillingURL = URL(string: "https://console.anthropic.com/settings/billing")

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    /// Creates a Claude provider whose refresh yields a snapshot on the given account tier.
    private func makeClaude(tier: AccountTier?) -> ClaudeProvider {
        let probe = MockUsageProbe()
        given(probe).probe().willReturn(
            UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date(), accountTier: tier)
        )
        given(probe).isAvailable().willReturn(true)
        return ClaudeProvider(probe: probe, settingsRepository: makeSettingsRepository())
    }

    @Test
    func `dashboard opens claude.ai usage settings for a Max account`() async throws {
        let claude = makeClaude(tier: .claudeMax)

        try await claude.refresh()

        #expect(claude.dashboardURL == Self.subscriptionUsageURL)
    }

    @Test
    func `dashboard opens claude.ai usage settings for a Pro account`() async throws {
        let claude = makeClaude(tier: .claudePro)

        try await claude.refresh()

        #expect(claude.dashboardURL == Self.subscriptionUsageURL)
    }

    @Test
    func `dashboard opens claude.ai usage settings for other subscription plans`() async throws {
        let claude = makeClaude(tier: .custom("team"))

        try await claude.refresh()

        #expect(claude.dashboardURL == Self.subscriptionUsageURL)
    }

    @Test
    func `dashboard opens Console billing for an API account`() async throws {
        let claude = makeClaude(tier: .claudeApi)

        try await claude.refresh()

        #expect(claude.dashboardURL == Self.consoleBillingURL)
    }

    @Test
    func `dashboard opens claude.ai usage settings when the account tier is unknown`() async throws {
        let claude = makeClaude(tier: nil)

        try await claude.refresh()

        #expect(claude.dashboardURL == Self.subscriptionUsageURL)
    }

    @Test
    func `dashboard opens claude.ai usage settings before the first refresh`() {
        let claude = makeClaude(tier: .claudeApi)

        #expect(claude.dashboardURL == Self.subscriptionUsageURL)
    }
}
