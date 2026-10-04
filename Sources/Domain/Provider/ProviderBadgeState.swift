import Quotas
import DataSources
import Providers
import Foundation

/// What the header badge should say about one provider.
///
/// A provider with no snapshot used to fall back to `.healthy`, so a failed
/// probe showed a green "HEALTHY" pill above a card reading "Codex
/// Unavailable" (#259). Absence of data is its own state here, distinct from
/// data that says everything is fine.
public enum ProviderBadgeState: Equatable, Sendable {
    /// A refresh is in flight.
    case syncing
    /// The last probe failed, so there are no numbers to show.
    case unavailable
    /// Nothing to read with yet — no CLI on this Mac, or no sign-in (#198).
    /// Waiting for the person, not failing.
    case notSetUp
    /// Waiting for setup, but its usage is read — Claude Desktop's tokens
    /// without Claude Code. The person did set it up; the card says what the
    /// limits need, and the header says nothing (#198).
    case usageOnly
    /// No probe has produced data yet (first launch, provider just enabled).
    case awaitingData
    /// We have numbers, and this is what they say.
    case quota(QuotaStatus)

    /// - Parameters:
    ///   - isSyncing: whether a refresh is currently running.
    ///   - quotaStatus: status derived from the latest snapshot, nil when there is none.
    ///   - hasError: whether the last probe attempt failed.
    ///   - needsSetup: whether that failure is only that nothing is set up yet.
    ///   - readsUsage: whether usage history is read all the same.
    public init(isSyncing: Bool, quotaStatus: QuotaStatus?, hasError: Bool, needsSetup: Bool = false, readsUsage: Bool = false) {
        if isSyncing {
            self = .syncing
        } else if let quotaStatus {
            // Stale numbers still beat no numbers, so a snapshot wins over an
            // error from a later failed refresh.
            self = .quota(quotaStatus)
        } else if needsSetup {
            self = readsUsage ? .usageOnly : .notSetUp
        } else if hasError {
            self = .unavailable
        } else {
            self = .awaitingData
        }
    }

    /// Whether this state represents real usage data.
    public var hasData: Bool {
        if case .quota = self { return true }
        return false
    }
}
