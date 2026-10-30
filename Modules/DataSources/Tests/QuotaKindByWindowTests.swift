import DataSources
import Foundation
import Quotas
import Testing

/// A quota's kind can follow its window's length, not its place in the
/// answer: a plan whose only window is a week has no Session to show
/// (Codex Pro's primary window is the weekly one).
@Suite
struct QuotaKindByWindowTests {
    private func usage(_ body: String) throws -> UsageSnapshot {
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
        { "kind": "api", "fetch": { "http": { "url": "https://example.com" } }, "mapping": { "json": { "quotas": [
          { "kind": "session", "at": "$.primary", "usedPercent": "used",
            "window": [{ "seconds": "seconds" }, { "hours": 5 }],
            "kindByWindow": [{ "atLeast": { "days": 7 }, "kind": "weekly" }] },
          { "kind": "session", "at": "$.secondary", "usedPercent": "used",
            "window": [{ "seconds": "seconds" }, { "days": 7 }],
            "kindByWindow": [{ "atLeast": { "days": 7 }, "kind": "weekly" }] }
        ] } } }
        """.utf8))
        return try DataSources.make(definition, providerId: "codex").read(Response(status: 200, body: Data(body.utf8)))
    }

    @Test
    func `should call a window of a week Weekly even when the answer lists it first`() throws {
        let usage = try usage(#"{"primary":{"used":32,"seconds":604800},"secondary":null}"#)

        #expect(usage.quotas.map(\.quotaType) == [.weekly])
        #expect(usage.quotas.first?.windowDuration == 604800)
    }

    @Test
    func `should call a five-hour window Session and a week Weekly`() throws {
        let usage = try usage(#"{"primary":{"used":10,"seconds":18000},"secondary":{"used":20,"seconds":604800}}"#)

        #expect(usage.quotas.map(\.quotaType) == [.session, .weekly])
    }

    @Test
    func `should judge a window the answer gives no length for by the length the provider is known for`() throws {
        let usage = try usage(#"{"primary":{"used":10},"secondary":{"used":20}}"#)

        #expect(usage.quotas.map(\.quotaType) == [.session, .weekly])
    }
}
