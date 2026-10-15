#if os(Windows)
import Foundation
import WinSDK

/// Windows' zone: the registry key `GetDynamicTimeZoneInformation` gives,
/// never translated (Foundation reads the display name, which is in the
/// person's language, and so answers GMT: #565), joined to an IANA zone by
/// `WindowsZones`. It never loads the system `icu.dll`: once loaded,
/// Foundation's named zones are gone from the process.
struct WindowsTimeZone: TimeZoneSource {
    func current() -> TimeZone {
        var info = DYNAMIC_TIME_ZONE_INFORMATION()
        let state = GetDynamicTimeZoneInformation(&info)
        let key = withUnsafeBytes(of: info.TimeZoneKeyName) { bytes in
            String(decoding: bytes.bindMemory(to: UInt16.self).prefix { $0 != 0 }, as: UTF16.self)
        }
        // Minutes west of UTC, as the OS keeps it now: UTC = local + bias.
        var bias = Int(info.Bias)
        if state == DWORD(TIME_ZONE_ID_DAYLIGHT) {
            bias += Int(info.DaylightBias)
        } else if state == DWORD(TIME_ZONE_ID_STANDARD) {
            bias += Int(info.StandardBias)
        }
        return WindowsZones.zone(key: key, daylightSavingOff: info.DynamicDaylightTimeDisabled != 0,
                                 secondsFromGMT: -bias * 60)
    }
}
#endif
