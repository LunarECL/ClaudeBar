import Foundation
import Testing
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("Codex account isolation")
struct CodexAccountSetupTests {
    private func auth(at home: URL, email: String, accountId: String, token: String) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let claims = try JSONSerialization.data(withJSONObject: ["email": email])
        let jwt = "header." + claims.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".signature"
        let data = try JSONSerialization.data(withJSONObject: [
            "tokens": ["access_token": token, "refresh_token": "refresh-\(token)",
                       "account_id": accountId, "id_token": jwt],
            "last_refresh": ISO8601DateFormatter().string(from: Date())
        ])
        try data.write(to: home.appendingPathComponent("auth.json"))
    }

    @Test func `two homes retain separate identities and refresh destinations`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("account a")
        let b = root.appendingPathComponent("account b")
        try auth(at: a, email: "a@example.com", accountId: "account-a", token: "token-a")
        try auth(at: b, email: "b@example.com", accountId: "account-b", token: "token-b")
        let first = try CodexAccountSetup.configuration(codexHome: a.path, existingAccounts: [], defaultCodexHome: root.appendingPathComponent("default").path)
        let second = try CodexAccountSetup.configuration(codexHome: b.path, existingAccounts: [first], defaultCodexHome: root.appendingPathComponent("default").path)
        #expect(first.email == "a@example.com")
        #expect(second.email == "b@example.com")
        #expect(first.accountId != second.accountId)
        let loaderA = CodexCredentialLoader(codexHome: a.path)
        let loaderB = CodexCredentialLoader(codexHome: b.path)
        var credentials = try #require(loaderA.loadCredentials())
        credentials.accessToken = "refreshed-a"
        loaderA.saveCredentials(credentials)
        #expect(loaderA.loadCredentials()?.accessToken == "refreshed-a")
        #expect(loaderB.loadCredentials()?.accessToken == "token-b")
        #expect(loaderB.loadCredentials()?.refreshToken == "refresh-token-b")
    }

    @Test func `duplicate identity is rejected even from another directory`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a")
        let b = root.appendingPathComponent("b")
        try auth(at: a, email: "same@example.com", accountId: "same", token: "a")
        try auth(at: b, email: "same@example.com", accountId: "same", token: "b")
        let first = try CodexAccountSetup.configuration(codexHome: a.path, existingAccounts: [], defaultCodexHome: root.appendingPathComponent("default").path)
        #expect(throws: (any Error).self) {
            try CodexAccountSetup.configuration(codexHome: b.path, existingAccounts: [first], defaultCodexHome: root.appendingPathComponent("default").path)
        }
    }

    @Test func `unreadable credentials never fall back to default login`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("missing")
        #expect(CodexCredentialLoader(codexHome: home.path).loadCredentials() == nil)
        #expect(throws: (any Error).self) {
            try CodexAccountSetup.configuration(codexHome: home.path, existingAccounts: [], defaultCodexHome: root.appendingPathComponent("default").path)
        }
    }
    @Test func `reauthenticating a folder to another account fails closed`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try auth(at: root, email: "other@example.com", accountId: "other", token: "other-token")
        let probe = MockUsageProbe()
        given(probe).probe().willReturn(UsageSnapshot(providerId: "codex", quotas: [], capturedAt: Date()))
        let guarded = CodexAccountUsageProbe(probe: probe,
            credentialLoader: CodexCredentialLoader(codexHome: root.path), expectedAccountId: "original")
        #expect(await guarded.isAvailable() == false)
        await #expect(throws: ProbeError.self) { try await guarded.probe() }
    }

    @Test func `both modes display the saved login email`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try auth(at: root, email: "signed-in@example.com", accountId: "account", token: "access")
        let probe = MockUsageProbe()
        given(probe).probe().willReturn(UsageSnapshot(providerId: "codex", quotas: [], capturedAt: Date()))
        let guarded = CodexAccountUsageProbe(probe: probe,
            credentialLoader: CodexCredentialLoader(codexHome: root.path), expectedAccountId: "account")
        #expect(try await guarded.probe().accountEmail == "signed-in@example.com")
    }

    @Test func `same email with different workspace identities is not merged`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a")
        let b = root.appendingPathComponent("b")
        try auth(at: a, email: "same@example.com", accountId: "workspace-a", token: "a")
        try auth(at: b, email: "same@example.com", accountId: "workspace-b", token: "b")
        let first = try CodexAccountSetup.configuration(codexHome: a.path, existingAccounts: [], defaultCodexHome: root.appendingPathComponent("default").path)
        let second = try CodexAccountSetup.configuration(codexHome: b.path, existingAccounts: [first], defaultCodexHome: root.appendingPathComponent("default").path)
        #expect(first.accountId != second.accountId)
        #expect(first.probeConfig["chatgptAccountId"] != second.probeConfig["chatgptAccountId"])
    }

    @Test @MainActor func `saved accounts restore as independent selectable providers`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a")
        let b = root.appendingPathComponent("b")
        try auth(at: a, email: "a@example.com", accountId: "a", token: "a")
        try auth(at: b, email: "b@example.com", accountId: "b", token: "b")
        let defaults = root.appendingPathComponent("default").path
        let first = try CodexAccountSetup.configuration(codexHome: a.path, existingAccounts: [], defaultCodexHome: defaults)
        let second = try CodexAccountSetup.configuration(codexHome: b.path, existingAccounts: [first], defaultCodexHome: defaults)
        let file = root.appendingPathComponent("settings.json")
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
        settings.addAccount(first, forProvider: "codex")
        settings.addAccount(second, forProvider: "codex")
        let restored = JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
        let configs = restored.accounts(forProvider: "codex")
        #expect(configs.count == 2)
        let providers = configs.compactMap { CodexAccountSetup.provider(configuration: $0, settingsRepository: restored) }
        #expect(providers.map(\.name) == ["a@example.com", "b@example.com"])
        #expect(Set(providers.map(\.id)).count == 2)
        providers[0].isEnabled = false
        #expect(providers[1].isEnabled)
        #expect(restored.isEnabled(forProvider: providers[0].id) == false)
        let alerter = NotificationAlerter(alertSender: MockAlertSender(), accountSettings: restored)
        #expect(alerter.providerDisplayName(for: providers[1].id) == "Codex · b@example.com")
        // Removing a link must not delete either account's credentials.
        restored.removeAccount(accountId: first.accountId, forProvider: "codex")
        #expect(restored.accounts(forProvider: "codex").map(\.accountId) == [second.accountId])
        #expect(CodexCredentialLoader(codexHome: a.path).loadCredentials()?.accountId == "a")
    }

}

@Suite("Codex scoped RPC")
struct CodexScopedRPCTests {
    @Test func `RPC processes use separate homes and file credentials`() {
        let a = DefaultCodexRPCClient(codexHome: "/tmp/codex a")
        let b = DefaultCodexRPCClient(codexHome: "/tmp/codex b")
        #expect(a.processEnvironment["CODEX_HOME"] == "/tmp/codex a")
        #expect(b.processEnvironment["CODEX_HOME"] == "/tmp/codex b")
        #expect(a.processEnvironment["OPENAI_API_KEY"] == nil)
        #expect(a.accountArguments == ["-c", "cli_auth_credentials_store=\"file\""])
        #expect(DefaultCodexRPCClient().accountArguments.isEmpty)
    }
}

@Suite("Codex RPC account identity")
struct CodexRPCAccountIdentityTests {
    @Test func `keychain backed logins get their email from the CLI`() async throws {
        let transport = MockRPCTransport()
        given(transport).send(.any).willReturn(())
        given(transport).close().willReturn(())
        var responses = [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"result":{"account":{"type":"chatgpt","email":"keychain@example.com","planType":"pro"}}}"#.utf8),
            Data(#"{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":20},"planType":"pro"}}}"#.utf8)
        ]
        given(transport).receive().willProduce { responses.removeFirst() }
        let client = DefaultCodexRPCClient(cliExecutor: MockCLIExecutor(), includeAccountIdentity: true)
        client.transportFactory = { _, _ in transport }
        let snapshot = try await CodexUsageProbe(client: client).probe()
        #expect(snapshot.accountEmail == "keychain@example.com")
        #expect(snapshot.lowestQuota?.percentRemaining == 80)
    }

    @Test func `scoped RPC failure cannot use the default TTY account`() async throws {
        let executor = MockCLIExecutor()
        given(executor).execute(binary: .any, args: .any, input: .any, timeout: .any,
                                workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "5h limit: 99% left"))
        let client = DefaultCodexRPCClient(cliExecutor: executor, codexHome: "/tmp/separate-codex")
        client.transportFactory = { _, _ in throw ProbeError.timeout }
        await #expect(throws: ProbeError.timeout) { try await client.fetchRateLimits() }
    }
}
