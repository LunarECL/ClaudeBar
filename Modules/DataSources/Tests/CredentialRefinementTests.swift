import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources

/// A key lookup that answers only when what it found matches (`match`),
/// adds fixed values to it (`with`), and reads a field from the first of
/// several paths — and `{{url#host}}` in a template.
@Suite
struct CredentialRefinementTests {
    private func lookup(_ json: String) throws -> CredentialLookup {
        try JSONDecoder().decode(CredentialLookup.self, from: Data(json.utf8))
    }

    private func reader(_ lookup: CredentialLookup, home: URL, environment: [String: String] = [:]) -> DataSource {
        let definition = DataSourceDefinition(kind: "api", credential: lookup,
                                              fetch: .http(HTTPRequest(url: "https://{{baseURL#host}}/usage")),
                                              mapping: .script(ScriptMapping(file: "none.js")))
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return DataSources.make(definition, providerId: "acme", cliExecutor: MockCLIExecutor(), network: network,
                                makeTransport: { _, _, _, _ in MockRPCTransport() }, environment: { environment[$0] },
                                homeDirectory: home, now: { Date() })
    }

    private func config(_ json: String) throws -> (URL, () -> Void) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: home.appendingPathComponent("config.json"))
        return (home, { try? FileManager.default.removeItem(at: home) })
    }

    private let acmeConfig = #"""
    {"jsonFile":{"path":"~/config.json","token":["$.env.TOKEN","$.providers.0.key"],"baseURL":["$.env.BASE_URL","$.providers.0.base_url"]},
     "match":{"baseURL":"(api\\.acme\\.test|cn\\.acme\\.test)"}}
    """#

    @Test
    func `a field is read from the first of its paths that answers`() async throws {
        let (home, cleanUp) = try config(#"{"providers":[{"key":"k-1","base_url":"https://cn.acme.test/v1"}]}"#)
        defer { cleanUp() }

        let response = try await reader(try lookup(acmeConfig), home: home).fetchResponse()

        #expect(response.status == 200)
    }

    @Test
    func `a lookup whose value doesn't match answers with no key — its token is never sent elsewhere`() async throws {
        let (home, cleanUp) = try config(#"{"env":{"TOKEN":"k-1","BASE_URL":"https://api.anthropic.com"}}"#)
        defer { cleanUp() }

        await #expect { try await reader(try lookup(acmeConfig), home: home).fetchResponse() } throws: {
            ($0 as? DataSourceError)?.reason == .authenticationRequired
        }
    }

    @Test
    func `with adds fixed values, never replacing what was found`() async throws {
        let refined = try lookup(#"{"environment":"ACME_KEY","with":{"baseURL":"https://api.acme.test/v1","token":"not-this"}}"#)
        #expect(refined.lookupOrder == ["$ACME_KEY"])
        let definition = DataSourceDefinition(kind: "api", credential: refined,
                                              fetch: .http(HTTPRequest(url: "https://{{baseURL#host}}/usage", headers: ["Authorization": "Bearer {{token}}"])),
                                              mapping: .script(ScriptMapping(file: "none.js")))
        let network = MockNetworkClient()
        let seen = Seen()
        given(network).request(.any).willProduce { request in
            seen.request = request
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let source = DataSources.make(definition, providerId: "acme", cliExecutor: MockCLIExecutor(), network: network,
                                      makeTransport: { _, _, _, _ in MockRPCTransport() }, environment: { $0 == "ACME_KEY" ? "k-2" : nil },
                                      homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })

        _ = try await source.fetchResponse()

        #expect(seen.request?.url?.absoluteString == "https://api.acme.test/usage")
        #expect(seen.request?.value(forHTTPHeaderField: "Authorization") == "Bearer k-2")
    }

    @Test
    func `match and with round-trip as written`() throws {
        let refined = try lookup(acmeConfig)
        let again = try JSONDecoder().decode(CredentialLookup.self, from: JSONEncoder().encode(refined))
        #expect(again == refined)
    }
}

private final class Seen: @unchecked Sendable {
    var request: URLRequest?
}
