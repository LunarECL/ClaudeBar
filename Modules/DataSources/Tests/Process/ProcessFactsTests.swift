import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources

@Suite
struct ProcessFactsTests {
    private let localCall = LocalServerCall(app: "Acme", process: .init(names: ["acme-server"]), paths: ["/usage"])
    private let scriptCall = ScriptCall(run: "probe.sh", folder: "~/acme")

    @Test
    func `should retain a local server definition and disclose its loopback URLs`() throws {
        let fetch = Fetch.localServer(localCall)
        #expect(try JSONDecoder().decode(Fetch.self, from: JSONEncoder().encode(fetch)) == fetch)
        #expect(fetch.connection.urls == ["https://127.0.0.1:{{port}}/usage"])
    }

    @Test
    func `should never offer a login shell lookup when the platform has no shell connection`() {
        let platform = Platform(name: "Windows")
        #expect(DataSources.makeLoginShellEnvironment(platform: platform, cliExecutor: MockCLIExecutor()) == nil)
    }

    @Test
    func `should not describe unsupported scripts or local servers as running commands`() {
        let platform = Platform(name: "Windows")
        #expect(DataSources.scriptCommands(for: scriptCall, platform: platform).isEmpty)
        #expect(DataSources.localServerCommands(for: localCall, platform: platform).isEmpty)
    }

    @Test(arguments: [false, true])
    func `should name a missing script or server connection even when a generic command runner exists`(_ local: Bool) async {
        var platform = Platform(name: "Windows")
        platform.runCommand = { _ in MockCLIExecutor() }
        platform.localNetwork = MockNetworkClient()
        platform.processList = { [] }
        let fetch: Fetch = local ? .localServer(localCall) : .script(scriptCall)
        let source = DataSources.make(
            DataSourceDefinition(kind: "acme", fetch: fetch, mapping: .usage(UsageMapping())),
            providerId: "acme", platform: platform, network: MockNetworkClient(),
            environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() }
        )
        let what = local ? "Reading a local server" : "Running a script"
        #expect(await source.isReady())
        await #expect(throws: DataSourceError(.fetch, .executionFailed("\(what) isn't available on Windows yet."))) {
            try await source.fetchUsage()
        }
    }

    @Test
    func `should create the CLI trust directory under the supplied app data root`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cli-directory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var platform = Platform(name: "fixture")
        platform.applicationData = { home, _ in home.appendingPathComponent("AppData", isDirectory: true) }
        let directory = DataSources.cliWorkingDirectory(platform: platform, homeDirectory: root, environment: { _ in nil })
        #expect(directory == root.appendingPathComponent("AppData/ClaudeBar/Probe", isDirectory: true))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    #if os(macOS)
    @Test(.needsProcesses)
    func `should start a CLI in the supplied home's trust directory only when fetched`() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("cli-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent("Library/Application Support/ClaudeBar/Probe", isDirectory: true)
        let source = DataSources.make(
            DataSourceDefinition(kind: "acme", fetch: .command(CommandCall(cli: "/bin/pwd", workingDirectory: .dedicated)),
                                 mapping: .usage(UsageMapping())),
            providerId: "acme", platform: .current, network: MockNetworkClient(),
            environment: { _ in nil }, homeDirectory: home, now: { Date() }
        )
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let response = try await source.fetchResponse()
        let started = URL(fileURLWithPath: response.text.trimmingCharacters(in: .whitespacesAndNewlines), isDirectory: true)
        #expect(started.resolvingSymlinksInPath() == directory.resolvingSymlinksInPath())
    }

    @Test
    func `should keep the CLI directory the person already trusted`() {
        let trusted = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeBar/Probe", isDirectory: true)
        let directory = CLIWorkingDirectory.resolve()
        #expect(directory.standardizedFileURL == trusted.standardizedFileURL)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
    #endif

    #if os(Windows)
    @Test
    func `should not offer unavailable Mac shell or local server commands on Windows`() {
        #expect(DataSources.makeLoginShellEnvironment(cliExecutor: MockCLIExecutor()) == nil)
        #expect(Fetch.script(scriptCall).connection.commands.isEmpty)
        #expect(Fetch.localServer(localCall).connection.commands.isEmpty)
    }
    #endif
}
