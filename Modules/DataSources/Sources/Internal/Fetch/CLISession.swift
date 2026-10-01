import Diagnostics
import Foundation

/// Whether the installed CLI accepts a call's session flags (#132).
///
/// One per fetcher: the provider binds its data sources for its lifetime, and
/// concurrent fetches of one data source consult and drop this from different
/// tasks — so it is an actor, and the drop is seen by every later run.
actor SessionFlagLatch {
    private(set) var supported = true

    /// Whether the flags are still trusted.
    var isSupported: Bool { supported }

    /// Gives up on the session flags for this fetcher's lifetime.
    func refuse() {
        supported = false
    }
}

/// The file that keeps the shared session's id between runs (#132).
///
/// Every failure is logged and read as "no session": the next run simply
/// creates a new one, so a broken file never breaks a fetch.
struct CLISessionFile: Sendable {
    let url: URL

    private struct Payload: Codable {
        let sessionID: String
    }

    /// The stored id, or `nil` when there is none — first run, empty, corrupt
    /// or unreadable.
    func load() -> String? {
        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let id = payload.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : id
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            AppLog.probes.error("Could not read the session id from \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Remembers the id of a session the CLI just created. A failure is logged
    /// and forgotten: the next run creates another session.
    func save(_ id: String) {
        do {
            try JSONEncoder().encode(Payload(sessionID: id)).write(to: url, options: .atomic)
        } catch {
            AppLog.probes.error("Could not save the session id to \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Forgets the id — the session is gone, or the CLI refused the flags.
    func clear() {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            AppLog.probes.error("Could not remove \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

/// Runs one CLI call inside a persisted, shared session (#132).
///
/// The plan: no stored id → create the session under a fresh id (the `create`
/// template) and remember it; a stored id → resume it (`resume` template);
/// the CLI says the session is gone → drop the id and create again; the run
/// exited non-zero naming a refused flag → give up on the flags for this
/// fetcher's lifetime and run the call's plain args from then on.
struct CLISessionRunner: Sendable {
    let call: CLICall
    let reuse: SessionReuse
    /// The call's resolved working directory — `nil` to inherit.
    let directory: URL?
    let makeExecutor: CLIFetcher.MakeExecutor
    let fileURL: URL
    let latch: SessionFlagLatch
    /// A fresh session id — a UUID in production.
    let nextID: @Sendable () -> String

    init(
        call: CLICall,
        reuse: SessionReuse,
        directory: URL?,
        makeExecutor: @escaping CLIFetcher.MakeExecutor,
        fileURL: URL,
        latch: SessionFlagLatch,
        nextID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.call = call
        self.reuse = reuse
        self.directory = directory
        self.makeExecutor = makeExecutor
        self.fileURL = fileURL
        self.latch = latch
        self.nextID = nextID
    }

    /// Runs the call under the session plan and answers what the screen showed.
    func run() async throws -> CLIResult {
        guard await latch.isSupported else { return try await plain() }
        let file = CLISessionFile(url: fileURL)
        if let stored = file.load() {
            let result = try await execute(reuse.resume, id: stored)
            if Self.isRefused(result, tokens: reuse.unsupportedOn) {
                return try await giveUp(file: file)
            }
            if Self.isGone(result.output, tokens: reuse.recreateOn) {
                AppLog.probes.info("\(call.cli): the stored session is gone, creating a new one")
                file.clear()
                return try await create(file: file)
            }
            return result
        }
        return try await create(file: file)
    }

    /// Creates the session under a fresh id and remembers it. The session
    /// exists the moment the CLI boots, so the id is safe to keep even if the
    /// run's screen goes on to fail parsing.
    private func create(file: CLISessionFile) async throws -> CLIResult {
        let id = nextID()
        let result = try await execute(reuse.create, id: id)
        if Self.isRefused(result, tokens: reuse.unsupportedOn) {
            return try await giveUp(file: file)
        }
        file.save(id)
        return result
    }

    /// Gives up on the flags for this fetcher's lifetime and runs the call the
    /// way it always has. The stored id — useless without the flags — is
    /// dropped so a downgrade never resumes into a refused session.
    private func giveUp(file: CLISessionFile) async throws -> CLIResult {
        AppLog.probes.info("\(call.cli) refused the session flags, continuing without session reuse")
        await latch.refuse()
        file.clear()
        return try await plain()
    }

    private func plain() async throws -> CLIResult {
        try await execute([], id: "")
    }

    /// Appends the template's args — `{{id}}` filled, empty template for the
    /// plain run — to the call's own args.
    private func execute(_ template: [String], id: String) async throws -> CLIResult {
        try await makeExecutor(call).execute(
            binary: call.cli,
            args: call.args + template.map { $0.replacingOccurrences(of: "{{id}}", with: id) },
            input: call.input,
            timeout: call.timeout,
            workingDirectory: directory,
            autoResponses: call.autoResponses
        )
    }

    /// True when a run both failed and named a refused flag. The words alone
    /// prove nothing — a hook's transcript can carry them — but a CLI build
    /// that rejects an option exits non-zero.
    static func isRefused(_ result: CLIResult, tokens: [String]) -> Bool {
        guard result.exitCode != 0 else { return false }
        return matches(result.output, tokens: tokens)
    }

    /// True when the output says the stored session no longer exists.
    static func isGone(_ output: String, tokens: [String]) -> Bool {
        matches(output, tokens: tokens)
    }

    private static func matches(_ output: String, tokens: [String]) -> Bool {
        !tokens.isEmpty && tokens.contains { output.localizedCaseInsensitiveContains($0) }
    }

    /// Where the session file lives: an absolute (or `~`, or `${VAR}`) path as
    /// it stands; a relative path in the call's dedicated working directory,
    /// or home when the call has none.
    static func fileURL(
        _ file: String,
        workingDirectory: WorkingDirectory?,
        homeDirectory: URL,
        environment: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) -> URL {
        let expanded = Paths.expand(file, homeDirectory: homeDirectory, environment: environment)
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        switch workingDirectory {
        case .dedicated: return CLIWorkingDirectory.resolve().appendingPathComponent(expanded)
        default: return homeDirectory.appendingPathComponent(expanded)
        }
    }
}
