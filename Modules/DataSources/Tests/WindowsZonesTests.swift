import Foundation
import Testing
@testable import DataSources

/// Windows names a person's zone by a key (`Korea Standard Time`), and
/// Foundation takes only IANA names; CLDR's `windowsZones` table, vendored,
/// joins the two (#565). Runs on every platform: the table and the choice
/// are neutral, only reading the key is Windows'.
@Suite
struct WindowsZonesTests {
    /// 2026-07-15 12:00 UTC: summer in the northern hemisphere.
    private static let july = Date(timeIntervalSince1970: 1_784_116_800)

    @Test func `should name every Windows zone by an IANA zone this platform's Foundation has`() {
        let unknown = WindowsZones.iana.filter { TimeZone(identifier: $0.value) == nil }.map(\.key).sorted()
        #expect(unknown.isEmpty, "Foundation has no zone for: \(unknown)")
    }

    @Test(arguments: [
        ("Korea Standard Time", "Asia/Seoul"),
        ("Pacific Standard Time", "America/Los_Angeles"),
        ("W. Europe Standard Time", "Europe/Berlin"),
        ("UTC", "Etc/UTC"),
    ])
    func `should take a Windows zone key to its IANA zone, daylight saving and all`(key: String, iana: String) {
        let zone = WindowsZones.zone(key: key, daylightSavingOff: false, secondsFromGMT: 0)
        #expect(zone.identifier == iana)
    }

    @Test func `should keep the OS's offset, fixed, when the person turned daylight saving off`() {
        let zone = WindowsZones.zone(key: "Pacific Standard Time", daylightSavingOff: true, secondsFromGMT: -8 * 3600)
        #expect(zone.secondsFromGMT(for: Self.july) == -8 * 3600)
    }

    @Test func `should keep the OS's offset when the table doesn't know the key yet`() {
        let zone = WindowsZones.zone(key: "Atlantis Standard Time", daylightSavingOff: false, secondsFromGMT: 5 * 3600 + 1800)
        #expect(zone.secondsFromGMT(for: Self.july) == 5 * 3600 + 1800)
    }
}
