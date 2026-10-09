#if os(Windows)
import Foundation

/// Whether a line holds a fragment, byte for byte: the JSON lines reader's
/// prefilter. Windows' C runtime has no `memmem`, so each place the
/// fragment's first byte occurs (`memchr`) is compared whole (`memcmp`).
enum ByteSearch {
    static func contains(_ fragment: [UInt8], in line: UnsafeRawBufferPointer) -> Bool {
        guard let first = fragment.first else { return true }
        guard let base = line.baseAddress, line.count >= fragment.count else { return false }
        let last = line.count - fragment.count
        var offset = 0
        return fragment.withUnsafeBytes { needle in
            while offset <= last {
                guard let found = memchr(base + offset, Int32(first), last - offset + 1) else { return false }
                let at = base.distance(to: UnsafeRawPointer(found))
                if memcmp(base + at, needle.baseAddress!, fragment.count) == 0 { return true }
                offset = at + 1
            }
            return false
        }
    }
}
#endif
