import Foundation

/// Six-level urgency for the expected-pace tick, graded by the projected
/// end-of-period usage (usage% / timeElapsed%). Separate from `QuotaStatus`,
/// which colors the bar itself.
public enum PaceLevel: Int, Sendable, Comparable, CaseIterable {
    case comfortable = 0 // projected under 50%
    case onTrack = 1     // projected 50-75%
    case warming = 2     // projected 75-90%
    case pressing = 3    // projected 90-100%
    case critical = 4    // projected 100-120%
    case runaway = 5     // projected 120%+

    public static func < (lhs: PaceLevel, rhs: PaceLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The level for this usage, or nil before 3% of the period has elapsed
    /// or once it is over.
    /// - Parameters:
    ///   - percentUsed: How much quota has been consumed (0-100)
    ///   - percentTimeElapsed: How much of the reset period has elapsed (0-100)
    public static func from(percentUsed: Double, percentTimeElapsed: Double) -> PaceLevel? {
        guard percentTimeElapsed >= 3, percentTimeElapsed < 100 else { return nil }
        guard percentUsed > 0 else { return .comfortable }
        let projected = percentUsed / percentTimeElapsed
        switch projected {
        case ..<0.50: return .comfortable
        case 0.50..<0.75: return .onTrack
        case 0.75..<0.90: return .warming
        case 0.90..<1.00: return .pressing
        case 1.00..<1.20: return .critical
        default: return .runaway
        }
    }
}

extension UsageQuota {
    /// The pace level for the expected-pace tick, or nil when it cannot be graded.
    public var paceLevel: PaceLevel? {
        guard let percentTimeElapsed else { return nil }
        return PaceLevel.from(percentUsed: percentUsed, percentTimeElapsed: percentTimeElapsed)
    }
}
