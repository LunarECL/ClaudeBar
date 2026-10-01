import Domain
import Foundation

/// A data source's failure, naming the step that failed — *Couldn't read your
/// key* · *Couldn't connect* · *Couldn't find the numbers* — because each sends
/// the person somewhere different. `reason` is today's `ProbeError`, so
/// everything that already reads a `ProbeError` keeps reading one.
///
/// Never carries a secret or a response body.
public struct DataSourceError: Error, Sendable, Equatable, LocalizedError {
    public enum Step: String, Sendable, Equatable {
        case lookup
        case fetch
        case mapping
    }

    public let step: Step
    public let reason: ProbeError

    public init(_ step: Step, _ reason: ProbeError) {
        self.step = step
        self.reason = reason
    }

    public var errorDescription: String? {
        reason.errorDescription
    }

    /// Wraps any error thrown inside a step, keeping a `ProbeError` as it is.
    static func wrap(_ error: Error, as step: Step) -> DataSourceError {
        if let error = error as? DataSourceError { return error }
        if let reason = error as? ProbeError { return DataSourceError(step, reason) }
        return DataSourceError(step, .executionFailed(error.localizedDescription))
    }
}
