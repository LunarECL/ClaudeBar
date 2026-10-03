import DataSources
import Quotas
import Foundation
import Mockable
import Providers
import Testing

/// *TODAY'S USAGE* — what a login used, day by day, read from its tool's own
/// logs. The login owns it: `account.usageHistory`, `nil` when the provider
/// offers none or the login's logs aren't read.
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
        return UsageHistory(analyzer: analyzer)
    }

    private func login(_ id: String) -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: id, label: "", email: nil, probeConfig: ["codexHome": "/tmp/\(id)", "chatgptAccountId": id])
    }

    // MARK: - Reading

    @Test
    func `reading keeps today's usage`() async {
        let history = history(report(today: 14, previous: 41))

        await history.read()

        #expect(history.report?.today.totalCost == 14)
    }

    @Test
    func `a day with no usage on either side is kept as none`() async {
        let history = history(report(today: 0, previous: 0))

        await history.read()

        #expect(history.report == nil)
    }

    @Test
    func `only yesterday's usage is still kept`() async {
        let history = history(report(today: 0, previous: 41))

        await history.read()

        #expect(history.report?.previous.totalCost == 41)
    }

    @Test
    func `logs that can't be read leave the last report`() async {
        let analyzer = MockDailyUsageAnalyzing()
        given(analyzer).analyzeToday().willReturn(report(today: 14, previous: 41))
        let history = UsageHistory(analyzer: analyzer)
        await history.read()
        given(analyzer).analyzeToday().willThrow(CocoaError(.fileReadNoSuchFile))

        await history.read()

        #expect(history.report?.today.totalCost == 14)
    }

    // MARK: - The login owns it

    @Test
    func `the default login has the provider's usage history`() throws {
        let history = history(report(today: 14, previous: 41))
        let provider = try Providers.make("codex", settings: InMemoryProviderSettings(), usageHistory: history)

        #expect(provider.defaultAccount.usageHistory === history)
    }

    @Test
    func `an added login whose logs aren't read has none`() throws {
        let provider = try Providers.make("codex", settings: InMemoryProviderSettings(), accounts: [login("work")],
                                          usageHistory: history(report(today: 14, previous: 41)))

        #expect(provider.accounts.first { !$0.isDefault }?.usageHistory == nil)
    }

    @Test
    func `a provider that offers no usage history has none`() throws {
        let provider = try Providers.make("codex", settings: InMemoryProviderSettings())

        #expect(provider.defaultAccount.usageHistory == nil)
    }
}
