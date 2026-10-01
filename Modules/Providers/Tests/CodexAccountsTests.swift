import DataSources
import Domain
import Foundation
import Mockable
import Providers
import Testing

/// Codex's added accounts (#326) and its passive background (#216), all from
/// `codex.json`: the default login, and each login added by its folder.
@MainActor
@Suite
struct CodexAccountsTests {
    private static let usage = #"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":20}}}}"#

    // MARK: - The default login stays passive until checked (#216)

    @Test
    func `background refresh does not start codex before an explicit refresh succeeded`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(Self.usage)
        let codex = try stub.make("codex")

        await #expect(throws: ProbeError.self) { try await codex.refresh(.background) }

        #expect(stub.launches.count == 0)
        #expect(codex.lastError?.localizedDescription.contains("Click Refresh or Connect") == true)
    }

    @Test
    func `opening the popover does not start an unchecked codex`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(Self.usage)
        let codex = try stub.make("codex")

        await #expect(throws: ProbeError.self) { try await codex.refresh(.passive) }

        #expect(stub.launches.count == 0)
    }

    @Test
    func `an explicit refresh checks the session for later background refreshes`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(Self.usage)
        let codex = try stub.make("codex")

        try await codex.refresh()
        let background = try await codex.refresh(.background)

        #expect(stub.settings.isOn("verifiedAtLeastOnce", forProvider: "codex") == true)
        #expect(background.quota(for: .session)?.percentRemaining == 80)
        #expect(stub.launches.count == 2)
    }

    @Test
    func `a refresh through the api does not check the rpc session`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth(accountId: "account")
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"used_percent":10}}}"#)

        try await stub.make("codex").refresh()

        #expect(stub.settings.isOn("verifiedAtLeastOnce", forProvider: "codex") == nil)
    }

    @Test
    func `codex never starts without a login`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        try FileManager.default.removeItem(at: stub.home.appendingPathComponent(".codex/auth.json"))
        stub.answerRPC(Self.usage)
        stub.answerTerminal("5h limit: 99% left")

        await #expect(throws: ProbeError.authenticationRequired) { try await stub.make("codex").refresh() }

        #expect(stub.launches.count == 0)
    }

    @Test
    func `a keychain login gets its email from the cli`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(Self.usage, account: #"{"id":3,"result":{"account":{"type":"chatgpt","email":"keychain@example.com"}}}"#)

        let usage = try await stub.make("codex").refresh()

        #expect(usage.accountEmail == "keychain@example.com")
        #expect(usage.lowestQuota?.percentRemaining == 80)
    }

    // MARK: - Added accounts

    @Test
    func `an added account runs codex in its own folder with file credentials only`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let folder = try writeLogin(in: stub.home, "work", email: "work@example.com", accountId: "work")
        stub.answerRPC(Self.usage)
        let account = try stub.make("codex", account: config("a", folder: folder, accountId: "work"))

        try await account.refresh(.background)

        let launch = try #require(stub.launches.last)
        #expect(launch.environment?["CODEX_HOME"] == folder.path)
        #expect(launch.environment?["OPENAI_API_KEY"] == nil)
        #expect(launch.arguments.contains(#"cli_auth_credentials_store="file""#))
        #expect(stub.settings.isOn("verifiedAtLeastOnce", forProvider: "codex") == nil)
    }

    @Test
    func `added accounts keep their own ids, names and usage`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let a = try writeLogin(in: stub.home, "a", email: "a@example.com", accountId: "a")
        stub.answerRPC(Self.usage)
        let first = try stub.make("codex", account: config("a", folder: a, accountId: "a", email: "a@example.com"))
        let second = try stub.make("codex", account: config(
            "b", folder: stub.home.appendingPathComponent("signed-out"), accountId: "b", email: "b@example.com"
        ))

        let usage = try await first.refresh()
        await #expect(throws: ProbeError.self) { try await second.refresh() }

        #expect(first.id == "codex.a")
        #expect(second.id == "codex.b")
        #expect(first.name == "a@example.com")
        #expect(second.name == "b@example.com")
        #expect(usage.providerId == "codex.a")
        #expect(usage.quotas.first?.providerId == "codex.a")
        #expect(second.snapshot == nil)
        #expect(second.lastError != nil)
    }

    @Test
    func `both data sources show the login's email`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let folder = try writeLogin(in: stub.home, "work", email: "signed-in@example.com", accountId: "work")
        stub.answerRPC(Self.usage)
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"used_percent":10}}}"#)
        let account = try stub.make("codex", account: config("a", folder: folder, accountId: "work"))

        let viaRPC = try await account.refresh()
        account.use("api")
        let viaAPI = try await account.refresh()

        #expect(viaRPC.accountEmail == "signed-in@example.com")
        #expect(viaAPI.accountEmail == "signed-in@example.com")
    }

    @Test
    func `a folder signed in to another account fails closed`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let folder = try writeLogin(in: stub.home, "work", email: "other@example.com", accountId: "other")
        stub.answerRPC(Self.usage)
        given(stub.cli).locate(.any).willReturn("/usr/local/bin/codex")
        let account = try stub.make("codex", account: config("a", folder: folder, accountId: "original"))

        #expect(await account.isAvailable() == false)
        await #expect(throws: ProbeError.self) { try await account.refresh() }

        #expect(stub.launches.count == 0)
        #expect(account.lastError?.localizedDescription.contains("original account") == true)
    }

    // MARK: - Adding an account by its folder

    @Test
    func `two folders become two accounts with their own emails`() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try writeLogin(in: root, "account a", email: "a@example.com", accountId: "account-a")
        let b = try writeLogin(in: root, "account b", email: "b@example.com", accountId: "account-b")

        let first = try add(a, to: [], root: root)
        let second = try add(b, to: [first], root: root)

        #expect(first.email == "a@example.com")
        #expect(second.email == "b@example.com")
        #expect(first.accountId != second.accountId)
        #expect(first.probeConfig["chatgptAccountId"] == "account-a")
        #expect(first.probeConfig["codexHome"] == a.resolvingSymlinksInPath().path)
    }

    @Test
    func `one login is not added twice from another folder`() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try writeLogin(in: root, "a", email: "same@example.com", accountId: "same")
        let b = try writeLogin(in: root, "b", email: "same@example.com", accountId: "same")
        let first = try add(a, to: [], root: root)

        #expect(throws: ProbeError.executionFailed("This Codex account is already listed.")) {
            try add(b, to: [first], root: root)
        }
    }

    @Test
    func `one email in two workspaces is two accounts`() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try writeLogin(in: root, "a", email: "same@example.com", accountId: "workspace-a")
        let b = try writeLogin(in: root, "b", email: "same@example.com", accountId: "workspace-b")

        let first = try add(a, to: [], root: root)
        let second = try add(b, to: [first], root: root)

        #expect(first.probeConfig["chatgptAccountId"] != second.probeConfig["chatgptAccountId"])
    }

    @Test
    func `a folder without a login is refused`() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: ProbeError.executionFailed("No ChatGPT account found in this folder. Sign in with Codex using file credential storage, then choose the folder again.")) {
            try add(root.appendingPathComponent("missing"), to: [], root: root)
        }
    }

    @Test
    func `the default login's folder is refused`() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultFolder = try writeLogin(in: root, "default", email: "me@example.com", accountId: "me")

        #expect(throws: ProbeError.executionFailed("This is the default Codex login, which is already listed.")) {
            try add(defaultFolder, to: [], root: root)
        }
    }

    @Test
    func `saved accounts come back as separate providers`() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try writeLogin(in: root, "a", email: "a@example.com", accountId: "a")
        let b = try writeLogin(in: root, "b", email: "b@example.com", accountId: "b")
        let first = try add(a, to: [], root: root)
        let second = try add(b, to: [first], root: root)
        let settings = InMemoryProviderSettings()

        let providers = [first, second].compactMap { AddedAccounts.provider("codex", configuration: $0, settings: settings) }
        providers[0].isEnabled = false

        #expect(providers.map(\.name) == ["a@example.com", "b@example.com"])
        #expect(Set(providers.map(\.id)).count == 2)
        #expect(providers[1].isEnabled)
        #expect(settings.isEnabled(forProvider: providers[0].id) == false)
    }

    // MARK: - Helpers

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-accounts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func add(_ folder: URL, to existing: [ProviderAccountConfig], root: URL) throws -> ProviderAccountConfig {
        try AddedAccounts.configuration(
            "codex", folder: folder.path, existing: existing,
            defaultFolder: root.appendingPathComponent("default").path
        )
    }

    private func config(_ id: String, folder: URL, accountId: String, email: String? = nil) -> ProviderAccountConfig {
        ProviderAccountConfig(
            accountId: id, label: "", email: email,
            probeConfig: ["codexHome": folder.path, "chatgptAccountId": accountId]
        )
    }

    /// A Codex folder signed in with file credentials: `auth.json` with an
    /// account id and an id token carrying the email.
    @discardableResult
    private func writeLogin(in root: URL, _ name: String, email: String, accountId: String) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let claims = try JSONSerialization.data(withJSONObject: ["email": email])
        let jwt = "header." + claims.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".signature"
        let auth: [String: Any] = [
            "tokens": ["access_token": "token-\(name)", "refresh_token": "refresh-\(name)",
                       "account_id": accountId, "id_token": jwt],
            "last_refresh": ISO8601DateFormatter().string(from: Date()),
        ]
        try JSONSerialization.data(withJSONObject: auth).write(to: folder.appendingPathComponent("auth.json"))
        return folder
    }
}
