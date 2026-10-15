import Foundation

/// A Windows person's zone, from what the OS says about it (#565). Windows
/// names a zone by a registry key (`Korea Standard Time`) that Foundation
/// doesn't take; CLDR's `windowsZones` (`iana`, generated from `Vendor/CLDR`)
/// joins the key to an IANA zone, the one ICU uses. Neutral, so it is tested
/// on every platform; only reading the key is Windows'.
enum WindowsZones {
    /// The key's IANA zone, with every daylight-saving change it has. The OS's
    /// own offset, fixed, when the person turned daylight saving's automatic
    /// adjustment off (the OS then keeps standard time all year), or when the
    /// table doesn't know the key: still the OS's fact for now, never a guess.
    static func zone(key: String, daylightSavingOff: Bool, secondsFromGMT: Int) -> TimeZone {
        if !daylightSavingOff, let name = iana[key], let zone = TimeZone(identifier: name) {
            return zone
        }
        // Windows' offsets lie within ±14 hours; Foundation takes up to ±18.
        return TimeZone(secondsFromGMT: secondsFromGMT)!
    }
}
