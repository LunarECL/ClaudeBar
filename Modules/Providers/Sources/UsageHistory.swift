import DataSources
import Foundation
import Observation
import Quotas

/// *TODAY'S USAGE* — what one login used, day by day, read from its tool's
/// own logs on this Mac. Not a meter: nothing is left or judged, and the
/// monitor never refreshes it; it is read when the popover opens. The login
/// owns it, as `account.usageHistory` (CANONICAL §2.1); how the days are
/// extracted is its provider's `usageHistory`, run as a `UsageLog`.
@MainActor
@Observable
public final class UsageHistory {
    /// Today's and yesterday's usage, once read and when either holds any.
    public private(set) var report: DailyUsageReport?

    private let log: UsageLog

    public init(log: UsageLog) {
        self.log = log
    }

    /// One day per date of `range`, every date present.
    public func days(in range: DateRange) async -> [DailyUsageStat] {
        await log.days(in: range)
    }

    /// Reads the logs again: today against yesterday. Two days with nothing
    /// are kept as none.
    public func read() async {
        let days = await log.days(last: 2)
        guard days.count == 2 else { return }
        let report = DailyUsageReport(today: days[1], previous: days[0])
        self.report = report.today.isEmpty && report.previous.isEmpty ? nil : report
    }
}
