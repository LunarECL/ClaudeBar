import DataSources
import Foundation
import Quotas
import Testing

/// A JSON mapping can read money — "$12.40 remaining", "of $50.00" — and a
/// balance with no ceiling reads as money with no percentage (Add Provider's
/// "never — a balance").
@Suite
struct MoneyQuotaTests {
    private func usage(_ mapping: String, _ body: String) throws -> UsageSnapshot {
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
        { "kind": "api", "fetch": { "http": { "url": "https://example.com" } }, "mapping": { "json": \(mapping) } }
        """.utf8))
        return try DataSources.make(definition, providerId: "openrouter").read(Response(status: 200, body: Data(body.utf8)))
    }

    @Test
    func `money with a limit is money of that limit`() throws {
        let usage = try usage("""
        { "quotas": [{ "kind": "time", "name": "Credits",
                       "left": { "money": "$.data.limit_remaining", "of": "$.data.limit", "currency": "USD" } }] }
        """, #"{"data":{"limit_remaining":12.4,"limit":50}}"#)

        let credits = try #require(usage.quotas.first)
        #expect(credits.left == .money(Money(Decimal(string: "12.4")!, currency: "USD"), of: Money(50, currency: "USD")))
        #expect(credits.percentLeft == 24.8)
    }

    @Test
    func `a balance has no percentage and no window`() throws {
        let usage = try usage("""
        { "quotas": [{ "kind": "time", "name": "Balance", "left": { "money": "$.balance" } }] }
        """, #"{"balance":7.5}"#)

        let balance = try #require(usage.quotas.first)
        #expect(balance.isBalance)
        #expect(balance.percentLeft == nil)
        #expect(balance.window == nil)
    }
}
