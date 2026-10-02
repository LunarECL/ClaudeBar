import Foundation

/// Keeps the usage records parsed from each session file between scans, so a scan
/// reads only what changed: nothing for an untouched file, the appended lines for a
/// growing one, and the whole file otherwise.
///
/// Appending is inferred from file metadata plus a hash of the bytes around the
/// already-read prefix; it is not proven. Claude Code appends to its session files,
/// but anything that fails these checks (a new inode, a shrink, coarse timestamps,
/// changed head or tail bytes) is read again from the start.
///
/// An actor, so overlapping scans run one after another and the later one finds the
/// earlier one's work already cached.
actor SessionLogCache {
    /// What the last scan did with each file it was given.
    struct ScanSummary: Equatable, Sendable {
        var reused = 0
        var extended = 0
        var reparsed = 0
    }

    private struct Entry {
        let stamp: FileStamp
        let endOffset: UInt64
        let prefixGuard: Int
        let records: [TokenUsageRecord]
        let tail: [TokenUsageRecord]
    }

    private static let guardBytes: UInt64 = 64 * 1024

    private let parser = SessionJSONLParser()
    private var entries: [URL: Entry] = [:]
    private(set) var lastScan = ScanSummary()

    var cachedFileCount: Int { entries.count }

    /// Usage records from `files`, in file order and line order within each file.
    /// Files not in `files` are dropped from the cache; unreadable ones are skipped.
    func records(in files: [URL]) -> [TokenUsageRecord] {
        var summary = ScanSummary()
        var kept: [URL: Entry] = [:]
        var records: [TokenUsageRecord] = []
        for url in files {
            guard let entry = refreshedEntry(for: url, summary: &summary) else { continue }
            kept[url] = entry
            records.append(contentsOf: entry.records)
            records.append(contentsOf: entry.tail)
        }
        entries = kept
        lastScan = summary
        return records
    }

    // MARK: - Private

    private func refreshedEntry(for url: URL, summary: inout ScanSummary) -> Entry? {
        // Stamp first: lines written while parsing then show up as a change next scan.
        guard let stamp = FileStamp(url: url) else { return nil }

        if let previous = entries[url], previous.stamp.isStrong, stamp.isStrong,
           previous.stamp.inode == stamp.inode {
            if previous.stamp == stamp {
                summary.reused += 1
                return previous
            }
            if stamp.size > previous.stamp.size,
               prefixGuard(of: url, length: previous.endOffset) == previous.prefixGuard,
               let chunk = try? parser.parse(fileURL: url, fromOffset: previous.endOffset),
               let guardHash = prefixGuard(of: url, length: chunk.endOffset) {
                summary.extended += 1
                return Entry(
                    stamp: stamp,
                    endOffset: chunk.endOffset,
                    prefixGuard: guardHash,
                    records: previous.records + chunk.records,
                    tail: chunk.tail
                )
            }
        }

        guard let chunk = try? parser.parse(fileURL: url, fromOffset: 0),
              let guardHash = prefixGuard(of: url, length: chunk.endOffset)
        else { return nil }
        summary.reparsed += 1
        return Entry(stamp: stamp, endOffset: chunk.endOffset, prefixGuard: guardHash, records: chunk.records, tail: chunk.tail)
    }

    /// Hash of the first and last `guardBytes` of the file's first `length` bytes:
    /// a bounded check that the part already read is still the same bytes.
    private func prefixGuard(of url: URL, length: UInt64) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = Hasher()
        hasher.combine(length)
        let headLength = min(length, Self.guardBytes)
        let tailStart = max(headLength, length - min(length, Self.guardBytes))
        do {
            hasher.combine(try handle.read(upToCount: Int(headLength)) ?? Data())
            try handle.seek(toOffset: tailStart)
            hasher.combine(try handle.read(upToCount: Int(length - tailStart)) ?? Data())
        } catch {
            return nil
        }
        return hasher.finalize()
    }
}

/// File metadata that changes whenever the file's content does.
struct FileStamp: Equatable, Sendable {
    let inode: UInt64
    let size: UInt64
    let modifiedNanos: Int64
    let changedNanos: Int64

    init?(url: URL) {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        inode = UInt64(info.st_ino)
        size = UInt64(info.st_size)
        modifiedNanos = Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        changedNanos = Int64(info.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(info.st_ctimespec.tv_nsec)
    }

    /// Whether the stamp can tell two versions of a file apart. A filesystem that keeps
    /// whole-second times could change a file twice with an identical stamp.
    var isStrong: Bool {
        inode != 0 && changedNanos % 1_000_000_000 != 0
    }
}
