import Foundation

/// A single token usage record extracted from a JSONL assistant message.
struct TokenUsageRecord: Sendable, Equatable {
    /// `message.id` (e.g. "msg_01Dso…"). Claude Code repeats this across streamed
    /// content blocks and parallel tool calls — used for deduplication. `nil` if absent.
    let messageId: String?
    /// Top-level `requestId` (e.g. "req_011Cax…"). Combined with `messageId` to form the
    /// dedup key. `nil` if absent.
    let requestId: String?
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let timestamp: Date

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}

/// Usage records read from part of a session file: the complete lines from the
/// starting offset onward, and any final line still missing its newline.
struct SessionLogChunk: Sendable, Equatable {
    /// Records from lines that end in a newline.
    let records: [TokenUsageRecord]
    /// Byte offset just past the last complete line; the next read resumes here.
    let endOffset: UInt64
    /// Records from a final line with no newline yet. Claude Code may still be
    /// writing it, so the next read parses it again instead of resuming inside it.
    let tail: [TokenUsageRecord]
}

/// Parses Claude Code session JSONL files to extract token usage records.
struct SessionJSONLParser {
    private static let readChunkSize = 1 << 20
    private static let newline = UInt8(ascii: "\n")
    /// Every usage-bearing line holds both of these byte sequences, so a line lacking
    /// either is skipped without being decoded. Inside a JSON string the quotes would be
    /// escaped (`\"usage\"`), so quoted mentions never match.
    private static let requiredFragments = [Array(#""usage""#.utf8), Array(#""assistant""#.utf8)]

    /// Parse a file from `offset` to its end, streaming it rather than loading it whole.
    func parse(fileURL: URL, fromOffset offset: UInt64) throws -> SessionLogChunk {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        let formatters = Formatters()
        var records: [TokenUsageRecord] = []
        var endOffset = offset
        var pending = Data()
        while let data = try handle.read(upToCount: Self.readChunkSize), !data.isEmpty {
            // `pending` holds no newline before this read, so only the new bytes need searching.
            let searchFrom = pending.count
            pending.append(data)
            let consumed = scanCompleteLines(in: pending, searchingFrom: searchFrom, formatters: formatters, into: &records)
            endOffset += UInt64(consumed)
            pending.removeSubrange(pending.startIndex..<pending.startIndex + consumed)
        }
        return SessionLogChunk(records: records, endOffset: endOffset, tail: parseTail(pending, formatters: formatters))
    }

    /// Parse content string directly.
    func parse(content: String) -> [TokenUsageRecord] {
        let data = Data(content.utf8)
        let formatters = Formatters()
        var records: [TokenUsageRecord] = []
        let consumed = scanCompleteLines(in: data, searchingFrom: 0, formatters: formatters, into: &records)
        return records + parseTail(data.dropFirst(consumed), formatters: formatters)
    }

    // MARK: - Private

    private final class Formatters {
        let fractional: ISO8601DateFormatter
        let whole: ISO8601DateFormatter

        init() {
            fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
        }

        func date(from string: String) -> Date? {
            fractional.date(from: string) ?? whole.date(from: string)
        }
    }

    /// Appends a record for each newline-terminated line in `data` and returns how
    /// many bytes those lines span. The first newline is searched for from
    /// `searchFrom`, which callers set past bytes already known to hold none.
    private func scanCompleteLines(
        in data: Data,
        searchingFrom searchFrom: Int,
        formatters: Formatters,
        into records: inout [TokenUsageRecord]
    ) -> Int {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            var lineStart = 0
            var searchStart = searchFrom
            while searchStart < buffer.count,
                  let found = memchr(base + searchStart, Int32(Self.newline), buffer.count - searchStart) {
                let lineEnd = UnsafeRawPointer(found) - base
                let line = UnsafeRawBufferPointer(rebasing: buffer[lineStart..<lineEnd])
                if let record = parseLine(line, formatters: formatters) {
                    records.append(record)
                }
                lineStart = lineEnd + 1
                searchStart = lineStart
            }
            return lineStart
        }
    }

    private func parseTail(_ data: Data, formatters: Formatters) -> [TokenUsageRecord] {
        data.withUnsafeBytes { parseLine($0, formatters: formatters) }.map { [$0] } ?? []
    }

    /// Extract a single record from one JSONL line, or `nil` if it is not a usage-bearing
    /// assistant message (or fails to parse).
    private func parseLine(_ line: UnsafeRawBufferPointer, formatters: Formatters) -> TokenUsageRecord? {
        guard let base = line.baseAddress,
              Self.requiredFragments.allSatisfy({ fragment in
                  memmem(base, line.count, fragment, fragment.count) != nil
              }),
              let json = try? JSONSerialization.jsonObject(with: Data(bytes: base, count: line.count)) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String,
              let timestampStr = json["timestamp"] as? String,
              let timestamp = formatters.date(from: timestampStr)
        else { return nil }

        return TokenUsageRecord(
            messageId: message["id"] as? String,
            requestId: json["requestId"] as? String,
            model: model,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            timestamp: timestamp
        )
    }
}
