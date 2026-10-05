import Testing
import Foundation
@testable import Domain

@Suite
struct QuotaStatusTests {

    // MARK: - Factory Method Tests

    @Test
    func `should call a quota healthy when 50 percent or more is left`() {
        #expect(QuotaStatus.from(percentRemaining: 100) == .healthy)
        #expect(QuotaStatus.from(percentRemaining: 75) == .healthy)
        #expect(QuotaStatus.from(percentRemaining: 51) == .healthy)
        #expect(QuotaStatus.from(percentRemaining: 50) == .healthy)
    }

    @Test
    func `should warn when between 20 and 49 percent is left`() {
        #expect(QuotaStatus.from(percentRemaining: 49) == .warning)
        #expect(QuotaStatus.from(percentRemaining: 35) == .warning)
        #expect(QuotaStatus.from(percentRemaining: 20) == .warning)
    }

    @Test
    func `should call a quota critical when between 1 and 19 percent is left`() {
        #expect(QuotaStatus.from(percentRemaining: 19) == .critical)
        #expect(QuotaStatus.from(percentRemaining: 10) == .critical)
        #expect(QuotaStatus.from(percentRemaining: 1) == .critical)
    }

    @Test
    func `should call a quota depleted when nothing or less is left`() {
        #expect(QuotaStatus.from(percentRemaining: 0) == .depleted)
        #expect(QuotaStatus.from(percentRemaining: -1) == .depleted)
        #expect(QuotaStatus.from(percentRemaining: -100) == .depleted)
    }

    // MARK: - Needs Attention Tests

    @Test
    func `should not ask for attention when a quota is healthy`() {
        #expect(QuotaStatus.healthy.needsAttention == false)
    }

    @Test
    func `should ask for attention when a quota is in warning`() {
        #expect(QuotaStatus.warning.needsAttention == true)
    }

    @Test
    func `should ask for attention when a quota is critical`() {
        #expect(QuotaStatus.critical.needsAttention == true)
    }

    @Test
    func `should ask for attention when a quota is depleted`() {
        #expect(QuotaStatus.depleted.needsAttention == true)
    }

    // MARK: - Comparison Tests (Severity Order)

    @Test
    func `should rank healthy as less severe than warning`() {
        #expect(QuotaStatus.healthy < QuotaStatus.warning)
    }

    @Test
    func `should rank warning as less severe than critical`() {
        #expect(QuotaStatus.warning < QuotaStatus.critical)
    }

    @Test
    func `should rank critical as less severe than depleted`() {
        #expect(QuotaStatus.critical < QuotaStatus.depleted)
    }

    @Test
    func `should rank depleted as the most severe status`() {
        #expect(QuotaStatus.depleted > QuotaStatus.healthy)
        #expect(QuotaStatus.depleted > QuotaStatus.warning)
        #expect(QuotaStatus.depleted > QuotaStatus.critical)
    }

    @Test
    func `should pick the worst of several statuses`() {
        let statuses: [QuotaStatus] = [.healthy, .warning, .critical]
        #expect(statuses.max() == .critical)

        let mixedStatuses: [QuotaStatus] = [.warning, .depleted, .healthy]
        #expect(mixedStatuses.max() == .depleted)
    }

    // MARK: - Equality Tests

    @Test
    func `should treat each status as equal to itself`() {
        #expect(QuotaStatus.healthy == .healthy)
        #expect(QuotaStatus.warning == .warning)
        #expect(QuotaStatus.critical == .critical)
        #expect(QuotaStatus.depleted == .depleted)
    }

    @Test
    func `should tell different statuses apart`() {
        #expect(QuotaStatus.healthy != .warning)
        #expect(QuotaStatus.warning != .critical)
        #expect(QuotaStatus.critical != .depleted)
    }

    // MARK: - Hashable Tests

    @Test
    func `should let each status carry its own color in a lookup`() {
        var dict: [QuotaStatus: String] = [:]
        dict[.healthy] = "green"
        dict[.warning] = "yellow"

        #expect(dict[.healthy] == "green")
        #expect(dict[.warning] == "yellow")
    }

    @Test
    func `should count a repeated status once in a set of statuses`() {
        let statuses: Set<QuotaStatus> = [.healthy, .warning, .healthy]
        #expect(statuses.count == 2)
    }

    // MARK: - Projected (Pace-Aware) Tests
    //
    // Pace-aware projects end-of-window usage as used / elapsed and colors by
    // the projection: under 70% healthy, 70-90% warning, 90%+ critical. Before
    // 15% of the window has elapsed, or once it is over, it uses fixed used%
    // thresholds: under 70% healthy, 70-90% warning, 90%+ critical.

    @Test
    func `should call a quota healthy under pace-aware when it projects under 70 percent`() {
        // 57% used, 85% elapsed → projects 67%
        #expect(QuotaStatus.from(percentRemaining: 43, percentTimeElapsed: 85, burnRateThreshold: 1.5) == .healthy)
        // 20% used, 50% elapsed → projects 40%
        #expect(QuotaStatus.from(percentRemaining: 80, percentTimeElapsed: 50, burnRateThreshold: 1.5) == .healthy)
    }

    @Test
    func `should warn under pace-aware when it projects 70 to 90 percent`() {
        // 60% used, 80% elapsed → projects 75%
        #expect(QuotaStatus.from(percentRemaining: 40, percentTimeElapsed: 80, burnRateThreshold: 1.5) == .warning)
        // 35% used, 50% elapsed → projects exactly 70%
        #expect(QuotaStatus.from(percentRemaining: 65, percentTimeElapsed: 50, burnRateThreshold: 1.5) == .warning)
    }

    @Test
    func `should call a quota critical under pace-aware when it projects 90 percent or more`() {
        // 30% used, 15% elapsed → projects 200%
        #expect(QuotaStatus.from(percentRemaining: 70, percentTimeElapsed: 15, burnRateThreshold: 1.5) == .critical)
        // 45% used, 50% elapsed → projects exactly 90%
        #expect(QuotaStatus.from(percentRemaining: 55, percentTimeElapsed: 50, burnRateThreshold: 1.5) == .critical)
    }

    @Test
    func `should judge a nearly spent quota by its projection under pace-aware`() {
        // 85% used, 99% elapsed → projects 86%: a warning, not critical
        #expect(QuotaStatus.from(percentRemaining: 15, percentTimeElapsed: 99, burnRateThreshold: 1.5) == .warning)
        // 90% used two minutes before a weekly reset → projects 90%: critical
        let twoMinutesLeft = 100 - (2.0 / (7 * 24 * 60)) * 100
        #expect(QuotaStatus.from(percentRemaining: 10, percentTimeElapsed: twoMinutesLeft, burnRateThreshold: 1.5) == .critical)
    }

    @Test
    func `should use fixed used thresholds under pace-aware before 15 percent of the window`() {
        #expect(QuotaStatus.from(percentRemaining: 50, percentTimeElapsed: 10, burnRateThreshold: 1.5) == .healthy)
        #expect(QuotaStatus.from(percentRemaining: 25, percentTimeElapsed: 10, burnRateThreshold: 1.5) == .warning)
        #expect(QuotaStatus.from(percentRemaining: 5, percentTimeElapsed: 14.9, burnRateThreshold: 1.5) == .critical)
        #expect(QuotaStatus.from(percentRemaining: 43, percentTimeElapsed: 0, burnRateThreshold: 1.5) == .healthy)
    }

    @Test
    func `should use fixed used thresholds under pace-aware once the window is over`() {
        #expect(QuotaStatus.from(percentRemaining: 20, percentTimeElapsed: 100, burnRateThreshold: 1.5) == .warning)
    }

    @Test
    func `should call an unused quota healthy under pace-aware`() {
        #expect(QuotaStatus.from(percentRemaining: 100, percentTimeElapsed: 50, burnRateThreshold: 1.5) == .healthy)
    }

    @Test
    func `should call an empty quota depleted under pace-aware however slowly it burned`() {
        #expect(QuotaStatus.from(percentRemaining: 0, percentTimeElapsed: 99, burnRateThreshold: 1.5) == .depleted)
    }

    @Test
    func `should ignore the burn rate threshold under pace-aware`() {
        // 55% used, 30% elapsed → projects 183% under any threshold
        #expect(QuotaStatus.from(percentRemaining: 45, percentTimeElapsed: 30, burnRateThreshold: 1.5) == .critical)
        #expect(QuotaStatus.from(percentRemaining: 45, percentTimeElapsed: 30, burnRateThreshold: 2.5) == .critical)
    }
}
