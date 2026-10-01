import Foundation
import Mockable

/// How the next probe run binds to the shared probe session (#132).
///
/// The probe keeps **one** Claude session alive across polls instead of
/// creating a new empty session per `/usage` run, which used to litter
/// `~/.claude/projects/` with a JSONL per poll and show up as an anonymous
/// "Probe" in session tools.
enum ProbeSessionPlan: Equatable, Sendable {
    /// First run (or after the stored session vanished): create the session
    /// under a fresh, stable id and give it the "ClaudeBar Probe" display name.
    case create(sessionID: String)
    /// Later runs: reuse the session that was created earlier.
    case resume(sessionID: String)
    /// The installed CLI does not support the session flags — today's behavior.
    case none
}

/// Persists the shared probe session's stable id between runs (#132).
@Mockable
public protocol ProbeSessionStore: Sendable {
    /// The stored session id, or nil when the next run should create one.
    func loadSessionID() -> String?
    /// Remembers the id of a session the CLI just created.
    func saveSessionID(_ id: String)
    /// Forgets the stored id, e.g. when the CLI can no longer find it.
    func clearSessionID()
}

/// File-backed `ProbeSessionStore` living in the probe working directory, so
/// the id survives app restarts (#132).
public struct FileProbeSessionStore: ProbeSessionStore, Sendable {
    private let fileURL: URL

    /// Stores the id as `<directory>/probe-session.json`.
    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("probe-session.json", isDirectory: false)
    }

    /// Stores the id in the dedicated probe working directory.
    public init() {
        self.init(directory: ProbeWorkingDirectory.resolve())
    }

    public func loadSessionID() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.sessionID.isEmpty else {
            return nil
        }
        return payload.sessionID
    }

    public func saveSessionID(_ id: String) {
        guard let data = try? JSONEncoder().encode(Payload(sessionID: id)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func clearSessionID() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private struct Payload: Codable {
        let sessionID: String
    }
}
