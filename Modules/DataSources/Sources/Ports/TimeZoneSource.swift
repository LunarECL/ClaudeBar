import Foundation
import Mockable

/// The person's time zone, as their OS has it now (MODULAR_DESIGN §10): the
/// zone a day of usage is counted in, a reset time without a zone is read in,
/// and a mapping script or a request is told. Never Foundation's `.current`,
/// which is GMT on Windows (#565). Read on each call, so a zone the person
/// changes is the next answer.
@Mockable
protocol TimeZoneSource: Sendable {
    func current() -> TimeZone
}

extension DataSources {
    /// The person's time zone, as their OS has it now: what another module or
    /// a client reads instead of `TimeZone.current`.
    public static func timeZone() -> TimeZone {
        Platform.current.timeZone.current()
    }

    /// The calendar a day is counted in: the system's, in the person's zone.
    /// What another module or a client reads instead of `Calendar.current`.
    public static func calendar() -> Calendar {
        Platform.current.calendar
    }
}
