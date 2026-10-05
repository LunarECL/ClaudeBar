import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources

/// `browserStorage` — a value a browser keeps for a site, read like a cookie
/// (ENGINE_DESIGN §2.9): every value from one browser profile, the first
/// profile with a token, never logged.
@Suite
struct BrowserStorageTests {
    private static let lookup = #"""
    {"browserStorage":{"origin":"https://app.devin.ai","values":{
      "token":{"key":"*auth1_session","path":"$.token"},
      "organization":{"key":"last-internal-org-for-external-org-v1-*"}}}}
    """#

    private func reader(_ stores: [[String: String]], lookup: String = Self.lookup) throws -> BrowserStorageReader {
        let port = MockBrowserStorageReading()
        given(port).stores(origin: .value("https://app.devin.ai")).willReturn(stores)
        guard case .browserStorage(let query) = try JSONDecoder().decode(CredentialLookup.self, from: Data(lookup.utf8)) else {
            throw CocoaError(.coderInvalidValue)
        }
        return BrowserStorageReader(query: query, storage: port)
    }

    @Test
    func `should read the token out of its JSON and the organization beside it`() throws {
        let store = ["persist:auth1_session": #"{"token":"auth1_abc","expires":1}"#,
                     "last-internal-org-for-external-org-v1-acme": #""org_123""#,
                     "unrelated": "x"]

        let credential = try #require(try reader([store]).find()).credential

        #expect(credential.token == "auth1_abc")
        #expect(credential["organization"] == "org_123")
    }

    @Test
    func `should take every value from the first profile that has a token, never mixing profiles`() throws {
        let noToken = ["last-internal-org-for-external-org-v1-other": #""org_other""#]
        let work = ["auth1_session": #"{"token":"work-token"}"#]
        let personal = ["auth1_session": #"{"token":"personal-token"}"#,
                        "last-internal-org-for-external-org-v1-me": #""org_me""#]

        let credential = try #require(try reader([noToken, work, personal]).find()).credential

        #expect(credential.token == "work-token")
        #expect(credential["organization"] == nil)
    }

    @Test
    func `should find no key when no profile keeps a token for the site`() throws {
        #expect(try reader([]).find()?.credential == nil)
        #expect(try reader([["auth1_session": "not json"]]).find()?.credential == nil)
        #expect(try reader([["auth1_session": #"{"other":"x"}"#]]).find()?.credential == nil)
    }

    @Test
    func `should read a key with no path as it is, a JSON string unquoted`() throws {
        let lookup = #"{"browserStorage":{"origin":"https://app.devin.ai","values":{"token":{"key":"session"}}}}"#
        #expect(try reader([["session": "plain"]], lookup: lookup).find()?.credential.token == "plain")
        #expect(try reader([["session": #""quoted""#]], lookup: lookup).find()?.credential.token == "quoted")
    }

    @Test
    func `should take the first of several matching keys in name order`() throws {
        let store = ["auth1_session": #"{"token":"t"}"#,
                     "last-internal-org-for-external-org-v1-b": #""org_b""#,
                     "last-internal-org-for-external-org-v1-a": #""org_a""#]
        #expect(try reader([store]).find()?.credential["organization"] == "org_a")
    }

    @Test
    func `should name the site in the lookup order and write the lookup back as it came`() throws {
        let lookup = try JSONDecoder().decode(CredentialLookup.self, from: Data(Self.lookup.utf8))
        #expect(lookup.lookupOrder == ["Browser storage · app.devin.ai"])
        #expect(try JSONDecoder().decode(CredentialLookup.self, from: try JSONEncoder().encode(lookup)) == lookup)
    }

    @Test
    func `should refuse a lookup that names no token`() {
        let lookup = #"{"browserStorage":{"origin":"https://app.devin.ai","values":{"organization":{"key":"org"}}}}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CredentialLookup.self, from: Data(lookup.utf8)) }
    }

    @Test
    func `should send the browser's token to the definition's host through a data source`() async throws {
        let port = MockBrowserStorageReading()
        given(port).stores(origin: .any).willReturn([["auth1_session": #"{"token":"auth1_abc"}"#,
                                                      "last-internal-org-for-external-org-v1-acme": #""org_123""#]])
        let network = MockNetworkClient()
        let seen = Seen()
        given(network).request(.any).willProduce { request in
            seen.request = request
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
        {"kind":"web","credential":\(Self.lookup),
         "fetch":{"http":{"url":"https://app.devin.ai/api/{{organization}}/usage","headers":{"Authorization":"Bearer {{token}}"}}},
         "mapping":{"json":{"quotas":[]}}}
        """.utf8))
        let source = DataSources.make(definition, providerId: "devin", cliExecutor: MockCLIExecutor(), network: network,
                                      makeTransport: { _, _, _, _ in MockRPCTransport() }, browserStorage: port,
                                      environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })

        _ = try await source.fetchResponse()

        #expect(seen.request?.url?.absoluteString == "https://app.devin.ai/api/org_123/usage")
        #expect(seen.request?.value(forHTTPHeaderField: "Authorization") == "Bearer auth1_abc")
    }

    final class Seen: @unchecked Sendable { var request: URLRequest? }
}
