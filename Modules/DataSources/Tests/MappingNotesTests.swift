import DataSources
import Foundation
import Quotas
import Testing

/// A JSON mapping can show a count the answer sends that is not a limit —
/// nothing is left of it and nothing refills — as a note beside the quotas:
/// "Usage limit resets · 1 · available".
@Suite
struct MappingNotesTests {
    private func usage(_ body: String) throws -> UsageSnapshot {
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
        { "kind": "api", "fetch": { "http": { "url": "https://example.com" } }, "mapping": { "json": {
          "quotas": [{ "kind": "session", "at": "$.primary", "usedPercent": "used" }],
          "notes": [{ "label": "Usage limit resets", "value": ["$.resets.count", "$.legacy_count"], "unit": "available" }]
        } } }
        """.utf8))
        return try DataSources.make(definition, providerId: "codex").read(Response(status: 200, body: Data(body.utf8)))
    }

    @Test
    func `should show a count the answer sends as a note with its unit`() throws {
        let usage = try usage(#"{"primary":{"used":10},"resets":{"count":2}}"#)

        #expect(usage.extensionMetrics == [ExtensionMetric(label: "Usage limit resets", value: "2", unit: "available")])
        #expect(usage.quotas.count == 1)
    }

    @Test
    func `should show a count of none rather than hide it`() throws {
        let usage = try usage(#"{"primary":{"used":10},"resets":{"count":0}}"#)

        #expect(usage.extensionMetrics?.first?.value == "0")
    }

    @Test
    func `should read the first place that answers`() throws {
        let usage = try usage(#"{"primary":{"used":10},"resets":null,"legacy_count":3}"#)

        #expect(usage.extensionMetrics?.first?.value == "3")
    }

    @Test(arguments: [#"{"primary":{"used":10}}"#, #"{"primary":{"used":10},"resets":{"count":null}}"#, #"{"primary":{"used":10},"resets":{"count":true}}"#])
    func `should show no note when the answer doesn't send the count`(_ body: String) throws {
        let usage = try usage(body)

        #expect(usage.extensionMetrics == nil)
    }
}
