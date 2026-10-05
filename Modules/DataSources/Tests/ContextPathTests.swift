import Foundation
import Quotas
import Testing
@testable import DataSources

/// `$context.<file>.<field>` in a JSON mapping — a value from a context file
/// the data source reads beside its answer, such as the email a tool keeps
/// in its own account file. The same reference `identity` and `accountId`
/// already use.
@Suite
struct ContextPathTests {
    private func mapping(_ json: String) throws -> JSONMapping {
        guard case .json(let mapping) = try JSONDecoder().decode(Mapping.self, from: Data(json.utf8)) else {
            throw CocoaError(.coderInvalidValue)
        }
        return mapping
    }

    private func read(_ mapping: JSONMapping, context: [String: [String: String]]) throws -> UsageSnapshot {
        try JSONMapper(mapping: mapping, now: { Date() })
            .read(Response(text: #"{"used":25}"#), facts: MappingFacts(context: context), providerId: "acme")
    }

    @Test
    func `should show the email a context file holds`() throws {
        let mapping = try mapping(#"{"json":{"email":["$context.account.email"],"quotas":[]}}"#)

        let usage = try read(mapping, context: ["account": ["email": "person@example.com"]])

        #expect(usage.accountEmail == "person@example.com")
    }

    @Test
    func `should show no email when the context file has none, and the next path still answers`() throws {
        let mapping = try mapping(#"{"json":{"email":["$context.account.email","$credential.email"],"quotas":[]}}"#)

        let none = try read(mapping, context: [:])
        let fallback = try JSONMapper(mapping: mapping, now: { Date() })
            .read(Response(text: "{}"), facts: MappingFacts(credential: ["email": "key@example.com"], context: ["account": [:]]),
                  providerId: "acme")

        #expect(none.accountEmail == nil)
        #expect(fallback.accountEmail == "key@example.com")
    }

    @Test
    func `should read a context value anywhere a mapping reads a path`() throws {
        let mapping = try mapping(#"{"json":{"quotas":[{"kind":"session","name":"Session","usedPercent":"$context.limits.used"}]}}"#)

        let usage = try read(mapping, context: ["limits": ["used": "40"]])

        #expect(usage.quota(for: .session)?.percentRemaining == 60)
    }
}
