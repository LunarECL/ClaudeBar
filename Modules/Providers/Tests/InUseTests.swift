import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// *In use* — which login new terminal sessions start with. Two Codex logins
/// are *me* (the plain login) and *work* (an added folder); choosing one
/// writes only its folder, and only new sessions follow it.
@MainActor
@Suite
struct InUseTests {
    // MARK: - Choosing

    @Test
    func `with nothing chosen, new sessions use the plain login`() throws {
        let (stub, codex, _) = try twoLogins()
        defer { stub.cleanUp() }

        #expect(codex.canChooseInUse)
        #expect(codex.inUse === codex.defaultAccount)
    }

    @Test
    func `choosing a login makes it the one in use, and records only its folder`() throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }

        try codex.use(work)

        #expect(codex.inUse === work)
        #expect(stub.loginsInUse.folder(for: "codex") == work.folder?.url)
    }

    @Test
    func `the login in use is still in use after a relaunch`() throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }
        try codex.use(work)

        let again = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))

        #expect(again.inUse.accountId == work.accountId)
    }

    @Test
    func `choosing the plain login clears the record`() throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }
        try codex.use(work)

        try codex.use(codex.defaultAccount)

        #expect(codex.inUse === codex.defaultAccount)
        #expect(stub.loginsInUse.folder(for: "codex") == nil)
    }

    @Test
    func `removing the login in use goes back to the plain login`() throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }
        try codex.use(work)

        codex.remove(work)

        #expect(codex.inUse === codex.defaultAccount)
        #expect(stub.loginsInUse.folder(for: "codex") == nil)
    }

    @Test
    func `a record naming a folder no login has is the plain login`() throws {
        let (stub, _, _) = try twoLogins()
        defer { stub.cleanUp() }
        try stub.loginsInUse.use(URL(fileURLWithPath: "/tmp/gone"), for: "codex")

        let codex = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))

        #expect(codex.inUse === codex.defaultAccount)
    }

    @Test
    func `another provider's login can't be put in use`() throws {
        let (stub, codex, _) = try twoLogins()
        defer { stub.cleanUp() }
        let claudeStub = try StubbedProvider(providerId: "claude")
        defer { claudeStub.cleanUp() }
        let claude = try claudeStub.makeProvider("claude")

        #expect(throws: (any Error).self) { try codex.use(claude.defaultAccount) }
        #expect(codex.inUse === codex.defaultAccount)
    }

    @Test
    func `a provider whose CLI has no login folder can't choose`() throws {
        let stub = try StubbedProvider(providerId: "gemini")
        defer { stub.cleanUp() }

        #expect(try stub.makeProvider("gemini").canChooseInUse == false)
    }

    @Test
    func `without a place to record it, nothing can be chosen`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try Providers.make("codex", settings: stub.settings)

        #expect(codex.canChooseInUse == false)
        #expect(throws: (any Error).self) { try codex.use(codex.defaultAccount) }
    }

    @Test
    func `a login is found by its name, its id, or default for the plain login`() throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }

        #expect(codex.account(named: "Work") === work)
        #expect(codex.account(named: "work") === work)
        #expect(codex.account(named: work.id) === work)
        #expect(codex.account(named: "default") === codex.defaultAccount)
        #expect(codex.account(named: "someone") == nil)
    }

    // MARK: - What each login can do — the screens only ask these

    @Test
    func `the login in use says so, and every folder login can be put in use`() throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }

        try work.useForNewSessions()

        #expect(work.isInUse)
        #expect(!codex.defaultAccount.isInUse)
        #expect(work.canBeInUse && codex.defaultAccount.canBeInUse)
        #expect(codex.loginsForNewSessions.map(\.id) == [codex.defaultAccount.id, work.id])
        #expect(codex.offersInUse)
    }

    @Test
    func `with one login there is nothing to choose between`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex")

        #expect(codex.canChooseInUse)
        #expect(!codex.offersInUse)
    }

    @Test
    func `a provider names the command and the variable its new sessions start with`() throws {
        let (stub, codex, _) = try twoLogins()
        defer { stub.cleanUp() }
        let gemini = try StubbedProvider(providerId: "gemini")
        defer { gemini.cleanUp() }

        #expect(codex.terminalCommand == TerminalCommand(name: "codex", variable: "CODEX_HOME", providerId: "codex"))
        #expect(try gemini.makeProvider("gemini").terminalCommand == nil)
    }

    // MARK: - Low: suggest, or switch when the person asked

    @Test
    func `when the login in use is low, the one with more left is suggested`() async throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }
        try await usage(stub, codex, me: 92, work: 15)

        #expect(codex.suggestedLogin === work)
    }

    @Test
    func `nothing is suggested while the login in use has room`() async throws {
        let (stub, codex, _) = try twoLogins()
        defer { stub.cleanUp() }
        try await usage(stub, codex, me: 40, work: 10)

        #expect(codex.suggestedLogin == nil)
    }

    @Test
    func `nothing is suggested when no other login has more left`() async throws {
        let (stub, codex, _) = try twoLogins()
        defer { stub.cleanUp() }
        try await usage(stub, codex, me: 92, work: 95)

        #expect(codex.suggestedLogin == nil)
    }

    @Test
    func `switch when low is off until the person turns it on`() async throws {
        let (stub, codex, _) = try twoLogins()
        defer { stub.cleanUp() }
        try await usage(stub, codex, me: 95, work: 10)

        #expect(codex.switchesWhenLow == false)
        #expect(try codex.switchIfLow() == nil)
        #expect(codex.inUse === codex.defaultAccount)
    }

    @Test
    func `below the threshold, new sessions move to the ticked login with the most left`() async throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }
        codex.switchesWhenLow = true
        codex.switchBelow = 10
        try await usage(stub, codex, me: 95, work: 10)

        let moved = try codex.switchIfLow()

        #expect(moved === work)
        #expect(codex.inUse === work)
        #expect(stub.loginsInUse.folder(for: "codex") == work.folder?.url)
    }

    @Test
    func `above the threshold nothing moves`() async throws {
        let (stub, codex, _) = try twoLogins()
        defer { stub.cleanUp() }
        codex.switchesWhenLow = true
        codex.switchBelow = 5
        try await usage(stub, codex, me: 90, work: 10)

        #expect(try codex.switchIfLow() == nil)
        #expect(codex.inUse === codex.defaultAccount)
    }

    @Test
    func `a login the person didn't tick is never switched to`() async throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }
        codex.switchesWhenLow = true
        codex.setMayPick(false, work)
        try await usage(stub, codex, me: 95, work: 10)

        #expect(codex.mayPick(work) == false)
        #expect(try codex.switchIfLow() == nil)
    }

    @Test
    func `switch when low and its choices are kept`() throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }
        codex.switchesWhenLow = true
        codex.switchBelow = 20
        codex.setMayPick(false, work)

        let again = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))

        #expect(again.switchesWhenLow)
        #expect(again.switchBelow == 20)
        #expect(again.mayPick(again.accounts[1]) == false)
        #expect(again.mayPick(again.defaultAccount))
    }

    // MARK: - After each refresh: what is worth telling the person

    @Test
    func `a login worth switching to is told once, not on every refresh`() async throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }
        try await usage(stub, codex, me: 92, work: 15)

        #expect(try codex.reviewInUse() == .worthSwitching(from: codex.defaultAccount, to: work))
        #expect(try codex.reviewInUse() == nil)
    }

    @Test
    func `after the login in use recovers, the next low is told again`() async throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }
        try await usage(stub, codex, me: 92, work: 15)
        _ = try codex.reviewInUse()

        try await usage(stub, codex, me: 30, work: 15)
        #expect(try codex.reviewInUse() == nil)
        try await usage(stub, codex, me: 95, work: 15)

        #expect(try codex.reviewInUse() == .worthSwitching(from: codex.defaultAccount, to: work))
    }

    @Test
    func `with switch when low on, the switch is what is told`() async throws {
        let (stub, codex, work) = try twoLogins()
        defer { stub.cleanUp() }
        codex.switchesWhenLow = true
        try await usage(stub, codex, me: 95, work: 15)

        #expect(try codex.reviewInUse() == .switched(from: codex.defaultAccount, to: work))
        #expect(codex.inUse === work)
    }

    // MARK: - Helpers

    /// Codex with the plain login *me* and an added folder login *work*.
    private func twoLogins() throws -> (StubbedProvider, Provider, Account) {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        try stub.writeCodexAuth(accountId: "me")
        let folder = stub.home.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let auth: [String: Any] = ["tokens": ["access_token": "token-work", "refresh_token": "refresh-work", "account_id": "work"],
                                   "last_refresh": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: auth).write(to: folder.appendingPathComponent("auth.json"))
        let config = ProviderAccountConfig(accountId: "work", label: "work", probeConfig: ["codexHome": folder.path, "chatgptAccountId": "work"])
        stub.settings.addAccount(config, forProvider: "codex")
        let codex = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))
        return (stub, codex, codex.accounts[1])
    }

    /// Both logins refreshed with these percentages used.
    private func usage(_ stub: StubbedProvider, _ codex: Provider, me: Int, work: Int) async throws {
        stub.network.reset([.given])
        for (id, used) in [("me", me), ("work", work)] {
            given(stub.network).request(.matching { @Sendable in $0.value(forHTTPHeaderField: "ChatGPT-Account-Id") == id })
                .willReturn((Data(#"{"rate_limit":{"primary_window":{"used_percent":\#(used)}}}"#.utf8), StubbedProvider.response(200)))
        }
        try await codex.defaultAccount.refresh()
        try await codex.accounts[1].refresh()
    }
}
