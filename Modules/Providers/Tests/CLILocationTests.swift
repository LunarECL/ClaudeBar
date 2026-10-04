import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// *CLI location* — where a provider's CLI lives on this Mac, when it isn't
/// the one ClaudeBar finds on its own (#210). One fact per provider: every
/// login, every CLI data source and Add Account's sign-in run it.
@MainActor
@Suite
struct CLILocationTests {
    private static let path = "/opt/tools/bin/codex-work"

    private func cli(of source: DataSource) -> String? {
        switch source.definition.fetch {
        case .cli(let call): call.cli
        case .jsonRpc(let call): call.cli
        default: nil
        }
    }

    private func login(_ id: String) -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: id, label: "", email: "\(id)@example.com",
                              probeConfig: ["codexHome": "/tmp/\(id)", "chatgptAccountId": id])
    }

    @Test
    func `should run the CLI from the chosen location for every login`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex", accounts: [login("work")], isExecutable: { _ in true })

        try codex.configuration.setCLIPath(Self.path)

        for account in codex.accounts {
            let clis = codex.dataSources(for: account).compactMap(cli)
            #expect(!clis.isEmpty)
            #expect(clis.allSatisfy { $0 == Self.path })
        }
        #expect(codex.configuration.cliPath == Self.path)
        #expect(stub.settings.cliPath(forProvider: "codex") == Self.path)
    }

    @Test
    func `should go back to finding the CLI as usual when the location is cleared`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex", isExecutable: { _ in true })
        try codex.configuration.setCLIPath(Self.path)

        try codex.configuration.setCLIPath("  ")

        #expect(codex.configuration.cliPath == nil)
        #expect(codex.dataSources(for: codex.defaultAccount).compactMap(cli).allSatisfy { $0 == "codex" })
        #expect(stub.settings.cliPath(forProvider: "codex") == nil)
    }

    @Test
    func `should refuse a location that is not a program and change nothing`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex", isExecutable: { _ in false })

        #expect(throws: UsageError.self) { try codex.configuration.setCLIPath("/Users/me/notes.txt") }

        #expect(codex.configuration.cliPath == nil)
        #expect(codex.dataSources(for: codex.defaultAccount).compactMap(cli).allSatisfy { $0 == "codex" })
    }

    @Test
    func `should use the saved CLI location after a relaunch`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        try stub.makeProvider("codex", isExecutable: { _ in true }).configuration.setCLIPath(Self.path)

        let relaunched = try stub.makeProvider("codex")

        #expect(relaunched.dataSources(for: relaunched.defaultAccount).compactMap(cli).allSatisfy { $0 == Self.path })
    }

    @Test
    func `should sign in a new account with the CLI at the chosen location`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex", isExecutable: { _ in true })
        try codex.configuration.setCLIPath(Self.path)
        let ran = Ran()
        let process = MockSignInProcess()
        given(process).run(executable: .any, arguments: .any, environment: .any, directory: .any, timeout: .any)
            .willProduce { @Sendable executable, _, _, _, _ in
                ran.executable = executable
                return 1
            }

        _ = try? await codex.accounts.signIn(with: AccountSignIn(process: process, folders: stub.folders, locate: { $0 }))

        #expect(ran.executable == Self.path)
    }
}

private final class Ran: @unchecked Sendable {
    var executable: String?
}
