import Foundation
import Mockable

/// *In use* — which login new terminal sessions of a provider start with:
/// one file per provider, `~/.claudebar/in-use/<provider>`, holding the
/// login's folder. Empty, or no file, is the plain login the CLI already
/// uses. The shell lines `ShellSetup` writes read it on every `claude` or
/// `codex`, so the file is the only record: nothing else keeps a copy.
@Mockable
public protocol LoginsInUse: Sendable {
    /// The folder new sessions of `providerId` start with — `nil` for the plain login.
    func folder(for providerId: String) -> URL?
    /// Saves it; `nil` goes back to the plain login.
    func use(_ folder: URL?, for providerId: String) throws
}

/// The real files, under `~/.claudebar/in-use`.
public struct DiskLoginsInUse: LoginsInUse {
    public static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claudebar/in-use", isDirectory: true)

    public let root: URL

    public init(root: URL = DiskLoginsInUse.root) {
        self.root = root
    }

    public func folder(for providerId: String) -> URL? {
        guard let text = try? String(contentsOf: file(for: providerId), encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path).standardizedFileURL
    }

    public func use(_ folder: URL?, for providerId: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Written whole and renamed into place, so a shell never reads half a path.
        try Data((folder?.standardizedFileURL.path ?? "").utf8).write(to: file(for: providerId), options: .atomic)
    }

    public func file(for providerId: String) -> URL {
        root.appendingPathComponent(providerId)
    }
}

/// What *In use* has to tell the person after a refresh.
public enum InUseNotice: Equatable {
    /// *Switch when low* moved new sessions from one login to another.
    case switched(from: Account, to: Account)
    /// The login in use is low and `to` has more left.
    case worthSwitching(from: Account, to: Account)

    public static func == (lhs: InUseNotice, rhs: InUseNotice) -> Bool {
        switch (lhs, rhs) {
        case let (.switched(a, b), .switched(c, d)), let (.worthSwitching(a, b), .worthSwitching(c, d)): a === c && b === d
        default: false
        }
    }
}

/// The command new terminal sessions run, and the variable that starts it on
/// a login's folder: `claude` with `CLAUDE_CONFIG_DIR`.
public struct TerminalCommand: Sendable, Equatable {
    public let name: String
    public let variable: String
    public let providerId: String

    public init(name: String, variable: String, providerId: String) {
        self.name = name
        self.variable = variable
        self.providerId = providerId
    }
}
