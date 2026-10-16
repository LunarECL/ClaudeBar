/// Helpers every mapping script gets, so a date is the person's: their zone
/// is `Platform.timeZone`, never the engine's own local time, which on Windows
/// applies today's offset to every date (#570). Instants are epoch seconds:
///
/// - `localParts(seconds)`: `{year, month, day, hours, minutes, seconds}` of
///   that instant on the person's clock, the month from 0 as `Date` has it;
/// - `localTime(year, month, day, hours, minutes, seconds)`: the instant the
///   person's clock reads that; a field past its range carries, as
///   `Date.UTC`'s do. A clock time the zone repeats is its first instant, and
///   one it skips moves forward by the gap, as `new Date(y, m, d, …)` does.
///
/// Both rest on the host's `zoneOffset(seconds)`: the zone's offset from UTC
/// at that instant, in seconds.
enum CalendarScript {
    static let source = #"""
function localParts(seconds) {
    const date = new Date((seconds + zoneOffset(seconds)) * 1000);
    return { year: date.getUTCFullYear(), month: date.getUTCMonth(), day: date.getUTCDate(),
             hours: date.getUTCHours(), minutes: date.getUTCMinutes(), seconds: date.getUTCSeconds() };
}
function localTime(year, month, day, hours, minutes, seconds) {
    const wall = Date.UTC(year, month, day, hours || 0, minutes || 0, seconds || 0) / 1000;
    // The offsets either side of any change near this clock time.
    const before = wall - zoneOffset(wall - 86400), after = wall - zoneOffset(wall + 86400);
    const reads = (instant) => instant + zoneOffset(instant) === wall;
    if (reads(before) && reads(after)) return Math.min(before, after);
    if (reads(after)) return after;
    return before;
}
"""#
}
