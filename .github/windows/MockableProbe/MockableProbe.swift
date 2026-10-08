import Mockable
import Testing

// Phase 0's question for Windows (MODULAR_DESIGN §10, Open): do @Mockable's
// macro and its mocks work with this toolchain? Quotas declares no ports, so
// this one stands in. Delete it in phase 2, once the DataSources and Providers
// tests, which mock every port this way, run on Windows.

@Mockable
protocol UsageSource {
    func percentLeft(of quota: String) async throws -> Double
}

@Test func `a mocked port answers what it was given, and counts its calls`() async throws {
    let source = MockUsageSource()
    given(source).percentLeft(of: .value("session")).willReturn(42)

    #expect(try await source.percentLeft(of: "session") == 42)
    verify(source).percentLeft(of: .any).called(1)
}
