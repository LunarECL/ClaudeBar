#if os(macOS)
import Foundation

extension FileStamp {
    /// The file's inode, size, and modification and change times to the nanosecond.
    init?(url: URL) {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        inode = UInt64(info.st_ino)
        size = UInt64(info.st_size)
        modifiedNanos = Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        changedNanos = Int64(info.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(info.st_ctimespec.tv_nsec)
    }
}
#endif
