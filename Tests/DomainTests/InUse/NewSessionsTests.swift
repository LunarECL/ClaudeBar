import Foundation
import Testing
@testable import Domain
@testable import Infrastructure

/// *New terminal sessions*: choosing which login each CLI starts with, and
/// the shell lines that make the choice count.
@MainActor
@Suite
struct NewSessionsTests {
    /// The shell lines, kept in memory.
    private final class Lines: ShellLines, @unchecked Sendable {
        var installed: Set<LoginShell> = []
        var failing = false
        func lines(for shell: LoginShell) -> String { "# lines for \(shell.rawValue)" }
        func file(for shell: LoginShell) -> URL { URL(fileURLWithPath: "/Users/you/.\(shell.rawValue)rc") }
        func isInstalled(_ shell: LoginShell) -> Bool { installed.contains(shell) }
        func install(_ shell: LoginShell) throws {
            if failing { throw CocoaError(.fileWriteNoPermission) }
            installed.insert(shell)
        }
        func remove(_ shell: LoginShell) throws { installed.remove(shell) }
    }

    private let temp = FileManager.default.temporaryDirectory.appendingPathComponent("new-sessions-\(UUID().uuidString)")
    private let lines = Lines()

    /// Codex with its plain login and an added folder login, *work*.
    private func codex() -> Provider {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent("settings.json")))
        let work = ProviderAccountConfig(accountId: "work", label: "work",
                                         probeConfig: ["codexHome": "/Users/you/.codex-work", "chatgptAccountId": "work"])
        return try! Providers.make("codex", settings: settings, accounts: [work],
                                   loginsInUse: DiskLoginsInUse(root: temp.appendingPathComponent("in-use")))
    }

    @Test
    func `with the lines in the shell, a chosen login is in use at once`() {
        lines.installed = [.zsh]
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)

        sessions.use(codex.accounts[1])

        #expect(codex.accounts[1].isInUse)
        #expect(sessions.waiting == nil)
    }

    @Test
    func `without the lines, the choice waits for the setup`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)

        sessions.use(codex.accounts[1])

        #expect(!codex.accounts[1].isInUse)
        #expect(sessions.isWaiting(in: codex))
    }

    @Test
    func `setting up writes the lines and makes the waiting choice`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .bash)
        sessions.use(codex.accounts[1])

        sessions.setUp()

        #expect(sessions.isSetUp)
        #expect(lines.installed == [.bash])
        #expect(codex.accounts[1].isInUse)
        #expect(sessions.waiting == nil)
    }

    @Test
    func `adding the lines by hand makes the choice and hands over the lines`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])

        let copied = sessions.setUpByHand()

        #expect(copied == "# lines for zsh")
        #expect(codex.accounts[1].isInUse)
    }

    @Test
    func `cancelling leaves the login in use as it was`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])

        sessions.cancel()

        #expect(codex.defaultAccount.isInUse)
        #expect(sessions.waiting == nil)
    }

    @Test
    func `the plain login never waits for the lines`() {
        lines.installed = [.zsh]
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])
        lines.installed = []

        sessions.use(codex.defaultAccount)

        #expect(codex.defaultAccount.isInUse)
        #expect(sessions.waiting == nil)
    }

    @Test
    func `turning off takes the lines out and every CLI back to its plain login`() {
        lines.installed = [.zsh]
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])

        sessions.turnOff()

        #expect(!sessions.isSetUp)
        #expect(lines.installed.isEmpty)
        #expect(codex.defaultAccount.isInUse)
    }

    @Test
    func `a setup that can't write says so, and keeps the choice waiting`() {
        lines.failing = true
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])

        sessions.setUp()

        #expect(sessions.problem?.contains("/Users/you/.zshrc") == true)
        #expect(sessions.isWaiting(in: codex))
    }

    @Test
    func `only products whose new sessions can be chosen are listed`() throws {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent("s.json")))
        let gemini = try Providers.make("gemini", settings: settings)
        let codex = codex()

        let sessions = NewSessions(products: [gemini, codex], shellLines: lines, shell: .zsh)

        #expect(sessions.products.map(\.id) == ["codex"])
        #expect(sessions.product("codex") === codex)
        #expect(sessions.product("gemini") == nil)
    }
}
