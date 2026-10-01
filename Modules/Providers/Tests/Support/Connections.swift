import DataSources
import Foundation
import Mockable
import Providers

/// Builds a built-in `Provider` whose data sources run on stubbed connections,
/// so a definition is tested end to end — lookup, fetch, mapping, lifecycle —
/// without a network, a CLI or the person's home directory.
@MainActor
struct StubbedProvider {
    let network = MockNetworkClient()
    let cli = MockCLIExecutor()
    let transport = MockRPCTransport()
    let home: URL
    let settings: InMemoryProviderSettings
    var environment: [String: String] = [:]

    init(dataSourceKind: String? = nil, providerId: String) throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("providers-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        settings = InMemoryProviderSettings(dataSourceKinds: dataSourceKind.map { [providerId: $0] } ?? [:])
    }

    func make(_ id: String) throws -> Provider {
        let definition = try Providers.builtIn(id)
        let transport = self.transport
        let environment = self.environment
        let sources = definition.dataSources.map {
            DataSources.make(
                $0,
                providerId: definition.id,
                cliExecutor: cli,
                network: network,
                makeTransport: { _, _, _ in transport },
                environment: { environment[$0] },
                homeDirectory: home,
                now: { Date() }
            )
        }
        return Provider(definition: definition, dataSources: sources, settings: settings)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Stubbing helpers

    /// Answers the JSON-RPC handshake's `initialize`, then `answer` for the call.
    func answerRPC(_ answer: String) {
        let received = Counter()
        given(transport).send(.any).willReturn(())
        given(transport).close().willReturn(())
        given(transport).receive().willProduce {
            Data((received.next() == 1 ? #"{"id":1,"result":{}}"# : answer).utf8)
        }
    }

    func answerHTTP(_ body: String, status: Int = 200, headers: [String: String] = [:]) {
        given(network).request(.any).willReturn((Data(body.utf8), Self.response(status, headers)))
    }

    func answerTerminal(_ screen: String) {
        given(cli).locate(.any).willReturn("/usr/local/bin/codex")
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: screen))
    }

    static func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    /// Writes `~/.codex/auth.json` in the stubbed home directory.
    func writeCodexAuth(token: String = "test-access-token", accountId: String? = nil, lastRefresh: Date = Date()) throws {
        let directory = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var tokens: [String: Any] = ["access_token": token, "refresh_token": "test-refresh-token"]
        if let accountId { tokens["account_id"] = accountId }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let auth: [String: Any] = ["tokens": tokens, "last_refresh": formatter.string(from: lastRefresh)]
        try JSONSerialization.data(withJSONObject: auth).write(to: directory.appendingPathComponent("auth.json"))
    }

    func readCodexAuth() throws -> [String: Any] {
        let url = home.appendingPathComponent(".codex/auth.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }
}

/// Counts calls across a mock's closure.
final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
