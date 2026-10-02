import CryptoKit
import DataSources
import Quotas
import Foundation
import Mockable
import Providers
import Testing

/// Claude's added accounts, all from `claude.json`: a second login lives in
/// its own config folder (`CLAUDE_CONFIG_DIR`), runs the same data sources
/// filled with that folder, and is told apart by the email its `.claude.json`
/// holds. The default login is untouched.
@MainActor
@Suite
struct ClaudeAccountsTests {
    private static let api = InMemoryProviderSettings(dataSourceKinds: ["claude": "api"])

    private func config(_ id: String, folder: URL, email: String) -> ProviderAccountConfig {
        ProviderAccountConfig(
            accountId: id, label: "", email: email,
            probeConfig: ["configDirectory": folder.path, "loginEmail": email, "credentialService": "fixture-\(id)"]
        )
    }

    /// Answers the usage API by bearer token: each login sees its own numbers.
    private func answerByToken(_ claude: ClaudeHarness, _ used: [String: Int]) {
        given(claude.network).request(.any).willProduce { @Sendable request in
            let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
            let body = #"{ "five_hour": { "utilization": \#(used[token] ?? 0) } }"#
            return (Data(body.utf8), ClaudeHarness.response(200))
        }
    }

    // MARK: - Each login reads its own folder

    @Test
    func `an added login reads its own key and its own email`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(accessToken: "default-token")
        try claude.writeClaudeConfig(email: "me@example.com")
        let work = try claude.writeLogin(in: "work", email: "work@example.com", token: "work-token")
        answerByToken(claude, ["default-token": 20, "work-token": 70])
        let provider = try claude.provider(settings: Self.api, accounts: [config("w", folder: work, email: "work@example.com")]).provider
        let (me, added) = (provider.accounts[0], provider.accounts[1])

        let mine = try await me.refresh()
        let theirs = try await added.refresh()

        #expect(added.id == "claude.w")
        #expect(mine.sessionQuota?.percentRemaining == 80)
        #expect(theirs.sessionQuota?.percentRemaining == 30)
        #expect(theirs.accountEmail == "work@example.com")
        #expect(theirs.providerId == "claude.w")
    }

    @Test
    func `a folder now signed in to someone else fails closed and the others keep their usage`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(accessToken: "default-token")
        let work = try claude.writeLogin(in: "work", email: "someone-else@example.com", token: "work-token")
        answerByToken(claude, ["default-token": 20, "work-token": 70])
        let provider = try claude.provider(settings: Self.api, accounts: [config("w", folder: work, email: "work@example.com")]).provider
        let (me, added) = (provider.accounts[0], provider.accounts[1])

        try await me.refresh()
        await #expect(throws: UsageError.self) { try await added.refresh() }

        #expect(added.snapshot == nil)
        #expect(added.lastError?.localizedDescription.contains("Reconnect the original Claude account") == true)
        #expect(me.snapshot?.sessionQuota?.percentRemaining == 80)
    }

    @Test
    func `the cli for an added login runs in its folder without the default login's keys`() throws {
        let sources = try Providers.builtIn("claude").dataSources(forAccount: [
            "configDirectory": "/Users/me/claude-work", "loginEmail": "work@example.com", "credentialService": "svc",
        ])

        for kind in ["cli", "cliCost"] {
            let source = try #require(sources.first { $0.kind == kind })
            guard case .cli(let call) = source.fetch else { Issue.record("\(kind) is not a CLI"); continue }
            #expect(call.environment.set["CLAUDE_CONFIG_DIR"] == "/Users/me/claude-work")
            #expect(call.environment.unset.contains("ANTHROPIC_API_KEY"))
            #expect(call.environment.unset.contains("CLAUDE_CODE_OAUTH_TOKEN"))
            #expect(source.context["account"]?.path == "/Users/me/claude-work/.claude.json")
            #expect(source.identity?.field == .context(file: "account", field: "email"))
            #expect(source.identity?.equals == "work@example.com")
        }
    }

    @Test
    func `folder trust is granted in the added login's own config`() throws {
        let sources = try Providers.builtIn("claude").dataSources(forAccount: [
            "configDirectory": "/Users/me/claude-work", "loginEmail": "work@example.com", "credentialService": "svc",
        ])
        let cli = try #require(sources.first { $0.kind == "cli" })

        guard case .patchJSONFile(let path, _, _)? = cli.recover["folderTrustRequired"] else {
            Issue.record("no folder-trust recovery"); return
        }
        #expect(path == "/Users/me/claude-work/.claude.json")
    }

    @Test
    func `the default login is untouched by the accounts block`() throws {
        let definition = try Providers.builtIn("claude")
        let cli = try #require(definition.dataSource("cli"))

        #expect(cli.identity == nil)
        #expect(cli.context["account"]?.path == "${CLAUDE_CONFIG_DIR:-~}/.claude.json")
    }

    // MARK: - Today's usage and guest passes are the default login's

    @Test
    func `today's usage and guest passes belong to the default login only`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let work = try claude.writeLogin(in: "work", email: "work@example.com", token: "work-token")
        answerByToken(claude, ["work-token": 70])
        let analyzer = MockDailyUsageAnalyzing()
        given(analyzer).analyzeToday().willReturn(DailyUsageReport(
            today: DailyUsageStat(date: Date(), totalCost: 14, totalTokens: 1, workingTime: 0, sessionCount: 1),
            previous: DailyUsageStat(date: Date(), totalCost: 41, totalTokens: 1, workingTime: 0, sessionCount: 1)
        ))
        let provider = try claude.provider(
            settings: Self.api,
            accounts: [config("w", folder: work, email: "work@example.com")],
            dailyUsage: analyzer,
            guestPasses: GuestPasses(source: MockGuestPassSource())
        ).provider
        let added = provider.accounts[1]

        let usage = try await added.refresh(.interactive)

        #expect(usage.dailyUsageReport == nil)
        #expect(added.guestPasses == nil)
        #expect(provider.defaultAccount.guestPasses != nil)
    }

    // MARK: - Add Account: choosing a signed-in folder

    @Test
    func `choosing a signed-in folder saves the folder, its email and its keychain service`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let work = try claude.writeLogin(in: "work", email: "work@example.com")

        let saved = try AddedAccounts.configuration(
            "claude", folder: work.path, existing: [], defaultFolder: "/nonexistent", makeDataSource: claude.make
        )

        let folder = try #require(saved.probeConfig["configDirectory"])
        let hash = SHA256.hash(data: Data(folder.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(saved.email == "work@example.com")
        #expect(saved.probeConfig["loginEmail"] == "work@example.com")
        #expect(saved.probeConfig["credentialService"] == "Claude Code-credentials-\(hash.prefix(8))")
    }

    @Test
    func `the same login is not added twice`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let work = try claude.writeLogin(in: "work", email: "work@example.com")
        let again = try claude.writeLogin(in: "work-again", email: "work@example.com")
        let saved = try AddedAccounts.configuration(
            "claude", folder: work.path, existing: [], defaultFolder: "/nonexistent", makeDataSource: claude.make
        )

        #expect(throws: UsageError.self) {
            try AddedAccounts.configuration("claude", folder: work.path, existing: [saved], defaultFolder: "/nonexistent", makeDataSource: claude.make)
        }
        #expect(throws: UsageError.self) {
            try AddedAccounts.configuration("claude", folder: again.path, existing: [saved], defaultFolder: "/nonexistent", makeDataSource: claude.make)
        }
    }

    @Test
    func `a folder with an email but no key is not a login`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let folder = try claude.writeLogin(in: "half", email: "half@example.com")
        try FileManager.default.removeItem(at: folder.appendingPathComponent(".credentials.json"))

        #expect(throws: UsageError.self) {
            try AddedAccounts.configuration("claude", folder: folder.path, existing: [], defaultFolder: "/nonexistent", makeDataSource: claude.make)
        }
    }

    @Test
    func `the default config folder is not added as a second login`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let folder = try claude.writeLogin(in: ".claude", email: "me@example.com")

        #expect(throws: UsageError.self) {
            try AddedAccounts.configuration("claude", folder: folder.path, existing: [], defaultFolder: folder.path, makeDataSource: claude.make)
        }
    }
}
