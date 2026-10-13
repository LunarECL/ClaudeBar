import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Quotas
import Testing
@testable import DataSources

@Suite
struct PlatformPathTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent("path-home-\(UUID().uuidString)")

    private func write(_ name: String, _ text: String, under root: URL) throws {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test
    func `should read the answer and its login context from the supplied app data folder`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let appData = home.appendingPathComponent("redirected roaming")
        try write("Acme/usage.json", #"{"used":35}"#, under: appData)
        try write("Acme/account.json", #"{"email":"fixture@example.test"}"#, under: appData)
        var platform = Platform.bare
        platform.applicationData = { _, _ in appData }
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data(#"{"kind":"file","fetch":{"file":{"path":"{{platform.appData}}/Acme/usage.json"}},"requiresFiles":["{{platform.appData}}/Acme/account.json"],"context":{"account":{"path":"{{platform.appData}}/Acme/account.json","email":"$.email"}},"mapping":{"json":{"email":"$context.account.email","quotas":[{"kind":"session","usedPercent":"$.used"}]}}}"#.utf8))
        let source = DataSources.make(definition, providerId: "acme", platform: platform, network: URLSession.shared,
                                      environment: { name in name == "platform.appData" ? "/wrong" : nil }, homeDirectory: home, now: { Date() })
        #expect(await source.isReady())
        let usage = try await source.fetchUsage()
        #expect(usage.accountEmail == "fixture@example.test")
        #expect(usage.quota(for: .session)?.percentRemaining == 65)
    }

    @Test
    func `should let an explicit environment folder override the portable default`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appendingPathComponent("custom")
        let appData = home.appendingPathComponent("application data")
        try write("usage.json", "chosen", under: custom)
        try write("usage.json", "default", under: appData)
        var platform = Platform.bare
        platform.applicationData = { _, _ in appData }
        let definition = DataSourceDefinition(kind: "file", fetch: .file(FileCall(path: "${ACME_HOME:-{{platform.appData}}}/usage.json")), mapping: .usage(UsageMapping()))
        let customPath = custom.path
        let source = DataSources.make(definition, providerId: "acme", platform: platform, network: URLSession.shared,
                                      environment: { $0 == "ACME_HOME" ? customPath : nil }, homeDirectory: home, now: { Date() })
        #expect(try await source.fetchResponse().text == "chosen")
        let fallback = DataSources.make(definition, providerId: "acme", platform: platform, network: URLSession.shared,
                                        environment: { _ in nil }, homeDirectory: home, now: { Date() })
        #expect(try await fallback.fetchResponse().text == "default")
    }

    @Test
    func `should not turn an unavailable app data folder into a root path or an environment credential`() {
        let missing = DataSources.expandPath("{{platform.appData}}/usage.json", platform: .bare, homeDirectory: home,
                                             environment: { _ in nil })
        #expect(missing == "{{platform.appData}}/usage.json")
        var platform = Platform.bare
        platform.applicationData = { _, _ in home }
        let definition = DataSourceDefinition(kind: "file", credential: .environment("platform.appData", loginShell: false),
                                              fetch: .file(FileCall(path: "~/usage.json")), mapping: .usage(UsageMapping()))
        let source = DataSources.make(definition, providerId: "acme", platform: platform, network: URLSession.shared,
                                      environment: { _ in nil }, homeDirectory: home, now: { Date() })
        #expect(!source.hasKey)
    }

    @Test
    func `should preserve a Windows drive and UNC root while accepting native path separators`() {
        let environment: @Sendable (String) -> String? = { $0 == "platform.pathSeparator" ? "\\" : nil }
        #expect(Paths.expand(#"C:\Users\A Person\AppData\Roaming\Acme\usage.json"#, homeDirectory: home, environment: environment)
                == "C:/Users/A Person/AppData/Roaming/Acme/usage.json")
        #expect(Paths.expand(#"\\server\share\Acme\usage.json"#, homeDirectory: home, environment: environment)
                == "//server/share/Acme/usage.json")
        #expect(Paths.expand(#"literal\file.json"#, homeDirectory: home, environment: { _ in nil }) == #"literal\file.json"#)
    }

    @Test
    func `should keep the whole portable default when a folder name contains the default separator`() {
        let appData = home.appendingPathComponent("application data").path
        let environment: @Sendable (String) -> String? = { $0 == "platform.appData" ? appData : nil }
        let expanded = Paths.expand("${CONFIG_HOME:-{{platform.appData}}/Acme:-archive}/usage.json",
                                    homeDirectory: home, environment: environment)
        #expect(expanded == appData + "/Acme:-archive/usage.json")
    }
}
