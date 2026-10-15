import Foundation
import Mockable
@testable import DataSources

/// A person's time zone, fixed: what `Platform.timeZone` answers in a test,
/// so a day's boundary is the same on every machine and every CI runner.
enum Zones {
    static func fixed(_ identifier: String) -> MockTimeZoneSource {
        let source = MockTimeZoneSource()
        given(source).current().willReturn(TimeZone(identifier: identifier)!)
        return source
    }

    /// Nine hours ahead of UTC with no daylight saving: a day there ends at
    /// 15:00 UTC, so a regression shows on a UTC runner.
    static var seoul: MockTimeZoneSource { fixed("Asia/Seoul") }
}

extension Platform {
    /// This platform with the person's zone fixed at `zone`.
    static func current(in zone: any TimeZoneSource) -> Platform {
        var platform = Platform.current
        platform.timeZone = zone
        return platform
    }
}
