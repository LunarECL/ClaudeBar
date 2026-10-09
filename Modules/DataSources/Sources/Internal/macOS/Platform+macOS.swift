#if os(macOS)
import Foundation

extension Platform {
    /// The Mac: every connection the engine has.
    static let current = Platform(
        name: "macOS",
        runCLI: CLIFetcher.system,
        runCommand: CommandFetcher.system,
        rpcTransport: { executable, arguments, environment, directory in
            try ProcessRPCTransport(executable: executable, arguments: arguments, environment: environment,
                                    workingDirectory: directory)
        },
        scriptEngine: JavaScriptCoreEngine(),
        keychain: KeychainReader.system,
        browserCookies: SystemBrowserCookies(),
        browserStorage: SystemBrowserStorage(),
        localNetwork: InsecureLocalhostNetworkClient(),
        processList: RunningProcesses.system,
        screenRenderer: { TerminalRenderer(cols: 160, rows: 50).render($0) },
        binaryLocator: BinaryLocator(),
        sqlite: { path, query, name in try ReadOnlyQuery.rows(at: path, query: query, name: name) }
    )
}
#endif
