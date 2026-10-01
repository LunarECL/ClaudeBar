import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Issue #140: hidden quota keys must stop driving the monitor's aggregates —
/// lowest quota, overall status, selected-provider status and alerts. A hidden
/// "Gemini Flash 2.0" must not color the provider.
@Suite
@MainActor
struct QuotaMonitorHiddenQuotasTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    /// Chicago-school alerter: records what it was told, tests assert state.
    private actor RecordingAlerter: QuotaAlerter {
        private(set) var alerts: [(providerId: String, previous: QuotaStatus, current: QuotaStatus)] = []

        func requestPermission() async -> Bool { true }

        func alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) async {
            alerts.append((providerId, previousStatus, currentStatus))
        }
    }

    /// Gemini-style snapshot: session and weekly healthy, flash critical (10%).
    private func makeGeminiProbe() -> MockUsageProbe {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "gemini",
            quotas: [
                UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "gemini"),
                UsageQuota(percentRemaining: 70, quotaType: .weekly, providerId: "gemini"),
                UsageQuota(percentRemaining: 10, quotaType: .modelSpecific("gemini-2.0-flash"), providerId: "gemini"),
            ],
            capturedAt: Date()
        ))
        return probe
    }

    private func makeSettings(hiddenKeys: Set<String>) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        given(mock).hiddenQuotaKeys(forProvider: .any).willReturn(hiddenKeys)
        return mock
    }

    private func makeRefreshedGeminiMonitor(
        hiddenKeys: Set<String>,
        alerter: (any QuotaAlerter)? = nil
    ) async -> (QuotaMonitor, MockProviderSettingsRepository) {
        let settings = makeSettings(hiddenKeys: hiddenKeys)
        let provider = GeminiProvider(probe: makeGeminiProbe(), settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            alerter: alerter,
            clock: TestClock(),
            settingsRepository: settings
        )
        await monitor.refresh(providerId: "gemini")
        return (monitor, settings)
    }

    // MARK: - Lowest Quota

    @Test
    func `lowest quota comes from visible quotas only`() async {
        // Given — the hidden flash model is the lowest of all
        let (monitor, _) = await makeRefreshedGeminiMonitor(hiddenKeys: ["model:gemini-2.0-flash"])

        // When & Then — the headline number promotes to the next-lowest visible quota
        #expect(monitor.lowestQuota()?.quotaType == .weekly)

        // And the same snapshot without hiding picks the flash model
        let (unhidden, _) = await makeRefreshedGeminiMonitor(hiddenKeys: [])
        #expect(unhidden.lowestQuota()?.quotaType == .modelSpecific("gemini-2.0-flash"))
    }

    @Test
    func `hiding every quota leaves no lowest quota`() async {
        let (monitor, _) = await makeRefreshedGeminiMonitor(
            hiddenKeys: ["session", "weekly", "model:gemini-2.0-flash"]
        )

        #expect(monitor.lowestQuota() == nil)
    }

    @Test
    func `monitor without settings treats nothing as hidden`() async {
        // Given — no settings repository wired (existing call sites)
        let settings = makeSettings(hiddenKeys: [])
        let provider = GeminiProvider(probe: makeGeminiProbe(), settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: TestClock()
        )
        await monitor.refresh(providerId: "gemini")

        // When & Then — behaviour is unchanged: all quotas count
        #expect(monitor.lowestQuota()?.quotaType == .modelSpecific("gemini-2.0-flash"))
        #expect(monitor.overallStatus == .critical)
    }

    // MARK: - Overall Status

    @Test
    func `overall status ignores hidden quotas`() async {
        // Given & When & Then — a hidden critical quota must not color the status
        let (hidden, _) = await makeRefreshedGeminiMonitor(hiddenKeys: ["model:gemini-2.0-flash"])
        #expect(hidden.overallStatus == .healthy)

        let (visible, _) = await makeRefreshedGeminiMonitor(hiddenKeys: [])
        #expect(visible.overallStatus == .critical)
    }

    @Test
    func `selected provider status ignores hidden quotas`() async {
        let (monitor, _) = await makeRefreshedGeminiMonitor(hiddenKeys: ["model:gemini-2.0-flash"])

        #expect(monitor.selectedProviderId == "gemini")
        #expect(monitor.selectedProviderStatus == .healthy)
    }

    // MARK: - Alerts

    @Test
    func `hidden quota status change does not alert`() async {
        // Given — the critical flash model is hidden
        let alerter = RecordingAlerter()
        let (monitor, _) = await makeRefreshedGeminiMonitor(
            hiddenKeys: ["model:gemini-2.0-flash"],
            alerter: alerter
        )
        _ = monitor

        // When & Then — the visible status is healthy, same as before the
        // refresh, so there is nothing to alert about
        #expect(await alerter.alerts.isEmpty)
    }

    @Test
    func `visible quota status change still alerts`() async {
        // Given — nothing hidden, so the snapshot is critical
        let alerter = RecordingAlerter()
        let (monitor, _) = await makeRefreshedGeminiMonitor(hiddenKeys: [], alerter: alerter)
        _ = monitor

        // Then — healthy → critical on first refresh
        #expect(await alerter.alerts.count == 1)
        #expect(await alerter.alerts.first?.providerId == "gemini")
        #expect(await alerter.alerts.first?.previous == .healthy)
        #expect(await alerter.alerts.first?.current == .critical)
    }
}
