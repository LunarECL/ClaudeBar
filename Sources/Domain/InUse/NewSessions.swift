import Foundation
import Mockable
import Observation
import Providers

/// The shell the lines are written for.
public enum LoginShell: String, CaseIterable, Sendable {
    case zsh, bash, fish

    /// The person's login shell, from `$SHELL` — zsh, macOS's own, when unknown.
    public static func login(_ path: String? = ProcessInfo.processInfo.environment["SHELL"]) -> LoginShell {
        let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        return LoginShell(rawValue: name) ?? .zsh
    }
}

/// The lines in the person's shell that start each CLI on the login in use —
/// what `NewSessions` needs from the disk.
@Mockable
public protocol ShellLines: Sendable {
    /// The lines as they would be written for `shell`.
    func lines(for shell: LoginShell) -> String
    /// The file they go in.
    func file(for shell: LoginShell) -> URL
    func isInstalled(_ shell: LoginShell) -> Bool
    func install(_ shell: LoginShell) throws
    func remove(_ shell: LoginShell) throws
}

/// *New terminal sessions* — which login each CLI starts with, and the shell
/// lines that make the choice count. A login chosen before the lines are in
/// the shell waits for them, so a switch never silently does nothing; the
/// plain login needs no lines and is never kept waiting.
@MainActor
@Observable
public final class NewSessions {
    public let products: [Provider]
    private let shellLines: any ShellLines

    /// The shell the lines are for — the login shell until the person picks another.
    public var shell: LoginShell {
        didSet { isSetUp = shellLines.isInstalled(shell) }
    }
    /// Whether the lines are in `shell`'s file.
    public private(set) var isSetUp: Bool
    /// The login chosen before the lines were there.
    public private(set) var waiting: Account?
    /// What went wrong last, in the person's words.
    public private(set) var problem: String?

    public init(products: [Provider], shellLines: any ShellLines, shell: LoginShell = .login()) {
        self.products = products.filter(\.canChooseInUse)
        self.shellLines = shellLines
        self.shell = shell
        self.isSetUp = shellLines.isInstalled(shell)
    }

    /// The lines as the setup shows them, and the file they go in.
    public var lines: String { shellLines.lines(for: shell) }
    public var file: URL { shellLines.file(for: shell) }

    /// The product `providerId` names, when its new sessions can be chosen.
    public func product(_ providerId: String) -> Provider? {
        products.first { $0.id == providerId }
    }

    /// Whether a choice for `product` waits for the setup.
    public func isWaiting(in product: Provider) -> Bool {
        waiting?.provider === product
    }

    /// *Use for new sessions* — at once when the lines are there (or for the
    /// plain login), else once they are set up.
    public func use(_ account: Account) {
        isSetUp = shellLines.isInstalled(shell)
        guard isSetUp || account.isDefault else {
            waiting = account
            return
        }
        apply(account)
    }

    /// *Add to ~/.zshrc* — writes the lines, then makes the waiting choice.
    public func setUp() {
        do {
            try shellLines.install(shell)
            isSetUp = true
            if let waiting { apply(waiting) }
            waiting = nil
        } catch {
            problem = "ClaudeBar couldn't write \(file.path): \(error.localizedDescription)"
        }
    }

    /// *Copy — I'll add it* — the person adds the lines; the choice is made
    /// now. Returns the lines to copy.
    public func setUpByHand() -> String {
        if let waiting { apply(waiting) }
        waiting = nil
        return lines
    }

    public func cancel() {
        waiting = nil
    }

    /// *Remove* — takes the lines out, and every CLI goes back to its plain login.
    public func turnOff() {
        do {
            try shellLines.remove(shell)
            isSetUp = false
            for product in products {
                try? product.use(product.defaultAccount)
            }
        } catch {
            problem = "ClaudeBar couldn't change \(file.path): \(error.localizedDescription)"
        }
    }

    private func apply(_ account: Account) {
        do {
            try account.useForNewSessions()
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}
