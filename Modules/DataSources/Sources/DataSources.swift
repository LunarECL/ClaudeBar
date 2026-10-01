import Foundation

/// The module's factory: the only place a case of `Fetch`, `Mapping` or
/// `CredentialLookup` meets the one connection it needs. Callers get a
/// `DataSource` and never name a worker.
public enum DataSources {
    /// Starts a CLI for a JSON-RPC conversation.
    public typealias TransportFactory = @Sendable (_ executable: String, _ arguments: [String], _ workingDirectory: URL?) throws -> any RPCTransport

    /// A data source on the real network, CLI and file system.
    public static func make(_ definition: DataSourceDefinition, providerId: String) -> DataSource {
        make(
            definition,
            providerId: providerId,
            cliExecutor: DefaultCLIExecutor(),
            network: URLSession.shared,
            makeTransport: { executable, arguments, directory in
                try ProcessRPCTransport(executable: executable, arguments: arguments, workingDirectory: directory)
            },
            environment: { ProcessInfo.processInfo.environment[$0] },
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            now: { Date() }
        )
    }

    /// The same, with each connection handed in — how tests, here and in the
    /// modules above, run real definitions over stubbed connections.
    public static func make(
        _ definition: DataSourceDefinition,
        providerId: String,
        cliExecutor: any CLIExecutor,
        network: any NetworkClient,
        makeTransport: @escaping TransportFactory,
        environment: @escaping @Sendable (String) -> String?,
        homeDirectory: URL,
        now: @escaping @Sendable () -> Date
    ) -> DataSource {
        let fetcher: any Fetching = switch definition.fetch {
        case .http(let request):
            HTTPFetcher(request: request, network: network, now: now)
        case .jsonRpc(let call):
            JSONRPCFetcher(call: call, cliExecutor: cliExecutor, makeTransport: makeTransport)
        case .cli(let call):
            CLIFetcher(call: call, cliExecutor: cliExecutor)
        }

        let mapper: any Reading = switch definition.mapping {
        case .json(let mapping): JSONMapper(mapping: mapping, now: now)
        case .text(let mapping): TextMapper(mapping: mapping, now: now)
        }

        var refresher: (any CredentialRefreshing)?
        var lookup = definition.credential
        if case .refreshing(let base, let oauth)? = lookup {
            refresher = OAuth2Refresher(refresh: oauth, network: network, now: now)
            lookup = base
        }

        return DataSource(
            definition: definition,
            providerId: providerId,
            credentials: lookup.map { reader(for: $0, environment: environment, homeDirectory: homeDirectory) },
            refresher: refresher,
            fetcher: fetcher,
            mapper: mapper
        )
    }

    private static func reader(
        for lookup: CredentialLookup,
        environment: @escaping @Sendable (String) -> String?,
        homeDirectory: URL
    ) -> any CredentialFinding {
        switch lookup {
        case .environment(let name):
            return EnvironmentReader(name: name, environment: environment)
        case .jsonFile(let file):
            return JSONFileReader(file: file, homeDirectory: homeDirectory)
        case .firstOf(let lookups):
            return FirstOfReader(readers: lookups.map { reader(for: $0, environment: environment, homeDirectory: homeDirectory) })
        case .refreshing(let base, _):
            // A refresh nested inside `firstOf` is refreshed by the outer data
            // source only; reading still works.
            return reader(for: base, environment: environment, homeDirectory: homeDirectory)
        }
    }
}
