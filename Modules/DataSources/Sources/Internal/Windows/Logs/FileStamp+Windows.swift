#if os(Windows)
import Foundation
import WinSDK

extension FileStamp {
    /// The file's NTFS file index (its inode), size, and last-write and change
    /// times, in the 100-nanosecond ticks Windows keeps them in. The change
    /// time moves whenever the file's content or attributes do, as `ctime`
    /// does on the Mac, so the reader can trust an unchanged stamp here too.
    init?(url: URL) {
        let handle = url.path.withCString(encodedAs: UTF16.self) { path in
            CreateFileW(path, DWORD(FILE_READ_ATTRIBUTES),
                        DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        defer { CloseHandle(handle) }
        var file = BY_HANDLE_FILE_INFORMATION()
        var times = FILE_BASIC_INFO()
        guard GetFileInformationByHandle(handle, &file),
              GetFileInformationByHandleEx(handle, FileBasicInfo, &times, DWORD(MemoryLayout<FILE_BASIC_INFO>.size))
        else { return nil }
        inode = UInt64(file.nFileIndexHigh) << 32 | UInt64(file.nFileIndexLow)
        size = UInt64(file.nFileSizeHigh) << 32 | UInt64(file.nFileSizeLow)
        modifiedNanos = Self.unixNanos(times.LastWriteTime.QuadPart)
        changedNanos = Self.unixNanos(times.ChangeTime.QuadPart)
    }

    /// Windows counts 100-nanosecond ticks from 1601, the Mac's stamp counts
    /// nanoseconds from 1970. Shifting the epoch first keeps the product inside
    /// `Int64`: ticks from 1601 times 100 overflow it, and trap, since 1893.
    private static func unixNanos(_ ticks: Int64) -> Int64 {
        (ticks - 116_444_736_000_000_000) * 100
    }
}
#endif
