import Foundation
import Testing
@testable import Infrastructure

@Suite
struct SessionLogCacheTests {
    private static func line(_ model: String, id: String = UUID().uuidString) -> String {
        #"{"type":"assistant","requestId":"req_\#(id)","message":{"id":"msg_\#(id)","model":"\#(model)","usage":{"input_tokens":10,"output_tokens":5}},"timestamp":"2026-03-11T10:00:00.000Z"}"#
    }

    private func makeFile(_ content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("session.jsonl")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func append(_ content: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(content.utf8))
    }

    /// Replaces the file's bytes while keeping its inode, the way an in-place rewrite would.
    private func overwriteInPlace(_ content: String, at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(content.utf8))
    }

    @Test func `reuses an unchanged file without reading it again`() async throws {
        let url = try makeFile(Self.line("claude-sonnet-4-6") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = SessionLogCache()

        _ = await cache.records(in: [url])
        let records = await cache.records(in: [url])

        #expect(records.map(\.model) == ["claude-sonnet-4-6"])
        #expect(await cache.lastScan == SessionLogCache.ScanSummary(reused: 1, extended: 0, reparsed: 0))
    }

    @Test func `reads only the lines appended since the last scan`() async throws {
        let url = try makeFile(Self.line("claude-sonnet-4-6") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = SessionLogCache()

        _ = await cache.records(in: [url])
        try append(Self.line("claude-opus-4-6") + "\n", to: url)
        let records = await cache.records(in: [url])

        #expect(records.map(\.model) == ["claude-sonnet-4-6", "claude-opus-4-6"])
        #expect(await cache.lastScan == SessionLogCache.ScanSummary(reused: 0, extended: 1, reparsed: 0))
    }

    @Test func `finishes a line that was half written at the last scan`() async throws {
        let opus = Self.line("claude-opus-4-6")
        let splitAt = opus.index(opus.startIndex, offsetBy: 40)
        let url = try makeFile(Self.line("claude-sonnet-4-6") + "\n" + String(opus[..<splitAt]))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = SessionLogCache()

        let before = await cache.records(in: [url])
        try append(String(opus[splitAt...]) + "\n", to: url)
        let after = await cache.records(in: [url])

        #expect(before.map(\.model) == ["claude-sonnet-4-6"])
        #expect(after.map(\.model) == ["claude-sonnet-4-6", "claude-opus-4-6"])
    }

    @Test func `counts a complete unterminated last line once after more is appended`() async throws {
        // Records without identity keys are never deduplicated downstream, so a
        // tail line counted twice would inflate the totals.
        let bare = #"{"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":10,"output_tokens":5}},"timestamp":"2026-03-11T10:00:00.000Z"}"#
        let url = try makeFile(Self.line("claude-sonnet-4-6") + "\n" + bare)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = SessionLogCache()

        let before = await cache.records(in: [url])
        try append("\n" + Self.line("claude-haiku-4-5") + "\n", to: url)
        let after = await cache.records(in: [url])

        #expect(before.map(\.model) == ["claude-sonnet-4-6", "claude-opus-4-6"])
        #expect(after.map(\.model) == ["claude-sonnet-4-6", "claude-opus-4-6", "claude-haiku-4-5"])
    }

    @Test func `reparses a file rewritten in place`() async throws {
        let url = try makeFile(Self.line("claude-sonnet-4-6") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = SessionLogCache()

        _ = await cache.records(in: [url])
        try overwriteInPlace(Self.line("claude-opus-4-6") + "\n" + Self.line("claude-haiku-4-5") + "\n", at: url)
        let records = await cache.records(in: [url])

        #expect(records.map(\.model) == ["claude-opus-4-6", "claude-haiku-4-5"])
        #expect(await cache.lastScan == SessionLogCache.ScanSummary(reused: 0, extended: 0, reparsed: 1))
    }

    @Test func `reparses a file that shrank`() async throws {
        let url = try makeFile(Self.line("claude-sonnet-4-6") + "\n" + Self.line("claude-opus-4-6") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = SessionLogCache()

        _ = await cache.records(in: [url])
        try overwriteInPlace(Self.line("claude-haiku-4-5") + "\n", at: url)
        let records = await cache.records(in: [url])

        #expect(records.map(\.model) == ["claude-haiku-4-5"])
    }

    @Test func `reparses a file replaced by a new one`() async throws {
        let url = try makeFile(Self.line("claude-sonnet-4-6") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = SessionLogCache()

        _ = await cache.records(in: [url])
        // An atomic write lands as a new file (new inode) at the same path.
        try (Self.line("claude-sonnet-4-6") + "\n" + Self.line("claude-opus-4-6") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        let records = await cache.records(in: [url])

        #expect(records.map(\.model) == ["claude-sonnet-4-6", "claude-opus-4-6"])
        #expect(await cache.lastScan == SessionLogCache.ScanSummary(reused: 0, extended: 0, reparsed: 1))
    }

    @Test func `forgets files that leave the scan`() async throws {
        let kept = try makeFile(Self.line("claude-sonnet-4-6") + "\n")
        let dropped = try makeFile(Self.line("claude-opus-4-6") + "\n")
        defer {
            try? FileManager.default.removeItem(at: kept.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: dropped.deletingLastPathComponent())
        }
        let cache = SessionLogCache()

        _ = await cache.records(in: [kept, dropped])
        let records = await cache.records(in: [kept])

        #expect(records.map(\.model) == ["claude-sonnet-4-6"])
        #expect(await cache.cachedFileCount == 1)
    }
}
