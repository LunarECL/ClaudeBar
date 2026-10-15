#if os(macOS)
import Foundation

/// The Mac's zone: Foundation's, which reads the system setting.
struct SystemTimeZone: TimeZoneSource {
    func current() -> TimeZone { .current }
}
#endif
