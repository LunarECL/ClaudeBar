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

    @Test(arguments: [
        ("UTC", 0),
        ("Mountain Standard Time (Mexico)", -7 * 3600),
        ("Yukon Standard Time", -7 * 3600),
        ("Qyzylorda Standard Time", 5 * 3600),
        ("Volgograd Standard Time", 3 * 3600),
    ])
    func `should keep the OS's offset for a zone Foundation on Windows can't format a date in`(key: String, offset: Int) {
        let zone = WindowsZones.zone(key: key, daylightSavingOff: false, secondsFromGMT: offset)
        #expect(!WindowsZones.unformattable.contains(zone.identifier))
        #expect(zone.secondsFromGMT(for: Self.july) == offset)
    }

    /// On Windows a formatter in a zone it can't use stops the whole process,
    /// so a zone a newer table brings in fails this run, not a person's app.
    @Test func `should give, for every Windows zone, a zone a date can be written out and read back in`() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let wrong = WindowsZones.iana.keys.sorted().compactMap { key -> String? in
            formatter.timeZone = WindowsZones.zone(key: key, daylightSavingOff: false, secondsFromGMT: 0)
            let text = formatter.string(from: Self.july)
            return formatter.date(from: text) == Self.july ? nil : "\(key): \(text)"
        }
        #expect(wrong.isEmpty, "\(wrong)")
    }
}
