import Foundation
import Testing
@testable import DataSources

/// `{ "environment": "X", "loginShell": true }` — a key exported only in the
/// person's shell profile is still found when the app starts from Finder
/// (#170). Only a lookup that says so waits for the shell.
@Suite
struct LoginShellLookupTests {
    final class Asked: @unchecked Sendable { var names: [String] = [] }

    private func lookup(_ json: String) throws -> CredentialLookup {
        try JSONDecoder().decode(CredentialLookup.self, from: Data(json.utf8))
    }

    @Test
    func `should find a key exported only in the login shell when the lookup asks for the shell`() throws {
        let asked = Asked()
        let reader = EnvironmentReader(name: "GLM_KEY", environment: { _ in nil }, loginShell: { name in
            asked.names.append(name)
            return name == "GLM_KEY" ? "from-shell" : nil
        })

        #expect(try reader.find()?.credential.token == "from-shell")
        #expect(asked.names == ["GLM_KEY"])
    }

    @Test
    func `should read the app's own environment first, without waiting for the shell`() throws {
        let asked = Asked()
        let reader = EnvironmentReader(name: "GLM_KEY", environment: { _ in "from-app" }, loginShell: { name in
            asked.names.append(name)
            return "from-shell"
        })

        #expect(try reader.find()?.credential.token == "from-app")
        #expect(asked.names.isEmpty)
    }

    @Test
    func `should never ask the shell for a lookup that doesn't say so`() async throws {
        let asked = Asked()
        let source = DataSources.make(
            try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
            {"kind":"api","credential":{"environment":"GLM_KEY"},
             "fetch":{"file":{"path":"~/nowhere.json"}},"mapping":{"json":{"quotas":[]}}}
            """.utf8)),
            providerId: "acme", cliExecutor: MockCLIExecutor(), network: MockNetworkClient(),
            makeTransport: { _, _, _, _ in MockRPCTransport() },
            loginShell: { name in asked.names.append(name); return "from-shell" },
            environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })

        _ = try? await source.fetchResponse()
        #expect(asked.names.isEmpty)
    }

    @Test
    func `should read and write the lookup as the definition says it`() throws {
        let shell = try lookup(#"{"environment":"GLM_KEY","loginShell":true}"#)
        let plain = try lookup(#"{"environment":"GLM_KEY"}"#)
        #expect(shell == .environment("GLM_KEY", loginShell: true))
        #expect(plain == .environment("GLM_KEY"))
        #expect(try JSONDecoder().decode(CredentialLookup.self, from: try JSONEncoder().encode(shell)) == shell)
        #expect(String(decoding: try JSONEncoder().encode(plain), as: UTF8.self) == #"{"environment":"GLM_KEY"}"#)
    }

    @Test
    func `should say in the lookup order that the login shell is read too`() throws {
        #expect(try lookup(#"{"environment":"GLM_KEY","loginShell":true}"#).lookupOrder == ["$GLM_KEY (also your login shell)"])
        #expect(try lookup(#"{"environment":"GLM_KEY"}"#).lookupOrder == ["$GLM_KEY"])
    }
}
