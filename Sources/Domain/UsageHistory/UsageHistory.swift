import Foundation
import Observation
import Providers

/// *TODAY'S USAGE* — today's and yesterday's cost and tokens, read from local
/// session logs. Not a meter, so it lives beside the providers rather than
/// inside any login's usage (CANONICAL §1).
///
/// A login has a usage history only when ClaudeBar reads that login's own
/// logs — `logs` is keyed by lineup id, and Claude's local logs are its
/// default login's (`claude`), never an added one's.
@MainActor
@Observable
public final class UsageHistory {
    private let logs: [String: any DailyUsageAnalyzing]
    public private(set) var reports: [String: DailyUsageReport] = [:]

    public init(logs: [String: any DailyUsageAnalyzing] = [:]) {
        self.logs = logs
    }

    /// Today's usage for a login, when its logs were read and held any.
    public func report(for lineupId: String) -> DailyUsageReport? {
        reports[lineupId]
    }

    /// Reads a login's logs again. A day with nothing on either side is kept
    /// as none; logs that can't be read leave the last report.
    public func read(for lineupId: String) async {
        guard let analyzer = logs[lineupId], let report = try? await analyzer.analyzeToday() else { return }
        reports[lineupId] = report.today.isEmpty && report.previous.isEmpty ? nil : report
    }
}
