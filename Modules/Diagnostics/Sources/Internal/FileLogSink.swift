import Foundation

/// The file log, for people: `[time] [LEVEL] [category] message`, one line
/// each, every level but `debug` (`notice` as `INFO`). Past `maxFileSize` the
/// file becomes `<name>.old.log` and a new one starts.
///
/// Lines are appended on a serial queue, so a log call never waits on the
/// disk; it is `@unchecked Sendable` because that queue is the only place its
/// file is touched.
final class FileLogSink: LogSink, @unchecked Sendable {
    let fileURL: URL
    private let maxFileSize: Int
    private let queue = DispatchQueue(label: "com.tddworks.ClaudeBar.FileLogSink")

    init(fileURL: URL, maxFileSize: Int = 5 * 1024 * 1024) {
        self.fileURL = fileURL
        self.maxFileSize = maxFileSize
        // Not through AppLog: this sink is how AppLog writes.
        let folder = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            NSLog("[FileLogSink] Failed to create logs directory at %@: %@", folder.path, error.localizedDescription)
        }
    }

    func write(_ level: LogLevel, category: String, message: String) {
        guard let label = Self.label(level) else { return }
        queue.async { [self] in
            rotateIfNeeded()
            let line = Data("[\(Self.timestamp())] [\(label)] [\(category)] \(message)\n".utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: line)
                }
            } else {
                try? line.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// Waits until every line written so far is in the file.
    func flush() {
        queue.sync {}
    }

    private static func label(_ level: LogLevel) -> String? {
        switch level {
        case .debug: nil
        case .info, .notice: "INFO"
        case .warning: "WARNING"
        case .error: "ERROR"
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func rotateIfNeeded() {
        // A fresh URL each time: a URL keeps the resource values it has read.
        guard let size = try? URL(filePath: fileURL.path).resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > maxFileSize else {
            return
        }
        let old = fileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: fileURL, to: old)
    }
}
