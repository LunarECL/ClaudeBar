import Foundation

/// The dedicated directory CLI probes run in.
///
/// Providers that gate on folder trust (Claude #44, Codex #267) prompt before
/// doing anything interactive. A probe that inherits the app's cwd — usually
/// `/` when launched from Finder or at login — stalls on that prompt, so the
/// probes run in this app-owned directory instead, where trust only needs to
/// be granted once and never blocks a refresh.
enum ProbeWorkingDirectory {
    /// Returns `Application Support/ClaudeBar/Probe`, creating it if needed.
    static func resolve() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("ClaudeBar", isDirectory: true)
            .appendingPathComponent("Probe", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
