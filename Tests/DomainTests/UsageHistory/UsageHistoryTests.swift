import Foundation
import Mockable
import Testing
@testable import Domain

/// *TODAY'S USAGE* — read from local session logs, not a meter, so it lives
/// beside the providers rather than inside any login's usage (CANONICAL §1).
/// A login has today's usage only when its own logs are read: Claude's are
/// the default login's.
@MainActor
@Suite
struct UsageHistoryTests {
    private func report(today: Decimal, previous: Decimal) -> DailyUsageReport {
        DailyUsageReport(
            today: DailyUsageStat(date: Date(), totalCost: today, totalTokens: today > 0 ? 1000 : 0,
                                  workingTime: today > 0 ? 60 : 0, sessionCount: today > 0 ? 1 : 0),
            previous: DailyUsageStat(date: Date().addingTimeInterval(-86400), totalCost: previous,
                                     totalTokens: previous > 0 ? 1000 : 0, workingTime: previous > 0 ? 60 : 0,
                                     sessionCount: previous > 0 ? 1 : 0)
        )
    }

    private func history(_ report: DailyUsageReport) -> UsageHistory {
        let analyzer = MockDailyUsageAnalyzing()
        given(analyzer).analyzeToday().willReturn(report)
        return UsageHistory(logs: ["claude": analyzer])
    }

    @Test
    func `reading today's usage keeps it for the login whose logs were read`() async {
        let history = history(report(today: 14, previous: 41))

        await history.read(for: "claude")

        #expect(history.report(for: "claude")?.today.totalCost == 14)
    }

    @Test
    func `a login whose logs ClaudeBar doesn't read has no usage history`() async {
        let history = history(report(today: 14, previous: 41))

        await history.read(for: "claude.work")

        #expect(history.report(for: "claude.work") == nil)
    }

    @Test
    func `a day with no usage on either side is kept as none`() async {
        let history = history(report(today: 0, previous: 0))

        await history.read(for: "claude")

        #expect(history.report(for: "claude") == nil)
    }

    @Test
    func `only yesterday's usage is still kept`() async {
        let history = history(report(today: 0, previous: 41))

        await history.read(for: "claude")

        #expect(history.report(for: "claude")?.previous.totalCost == 41)
    }

    @Test
    func `logs that can't be read leave the last report`() async {
        let analyzer = MockDailyUsageAnalyzing()
        given(analyzer).analyzeToday().willReturn(report(today: 14, previous: 41))
        let history = UsageHistory(logs: ["claude": analyzer])
        await history.read(for: "claude")
        given(analyzer).analyzeToday().willThrow(CocoaError(.fileReadNoSuchFile))

        await history.read(for: "claude")

        #expect(history.report(for: "claude")?.today.totalCost == 14)
    }
}
