import Domain
import Foundation
import Observation

/// *Share Claude Code* — a provider's guest passes: invitation links its plan
/// lets the person hand out. An action, not usage, so it lives beside the
/// provider's usage and never touches `lastError`.
@MainActor
@Observable
public final class GuestPasses {
    public private(set) var pass: ClaudePass?
    public private(set) var isFetching = false
    /// Separate from the provider's `lastError`: a failed pass fetch never
    /// marks usage unavailable.
    public private(set) var error: Error?

    private let probe: any ClaudePassProbing

    public init(probe: any ClaudePassProbing) {
        self.probe = probe
    }

    /// Offered only to a plan that can issue passes (#243).
    public func isOffered(for usage: UsageSnapshot?) -> Bool {
        usage?.accountTier?.supportsGuestPasses == true
    }

    @discardableResult
    public func fetch() async throws -> ClaudePass {
        isFetching = true
        defer { isFetching = false }
        do {
            let pass = try await probe.probe()
            self.pass = pass
            error = nil
            return pass
        } catch {
            self.error = error
            throw error
        }
    }

    public func clearError() {
        error = nil
    }
}
