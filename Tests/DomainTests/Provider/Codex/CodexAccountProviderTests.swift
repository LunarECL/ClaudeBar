import Foundation
import Testing
import Mockable
@testable import Domain

@Suite("Codex account providers")
@MainActor
struct CodexAccountProviderTests {
    @Test func `account instances have independent usage and identities`() async throws {
        let settings = MockProviderSettingsRepository()
        given(settings).isEnabled(forProvider: .any).willReturn(true)
        let aProbe = MockUsageProbe()
        let bProbe = MockUsageProbe()
        given(aProbe).probe().willReturn(UsageSnapshot(providerId: "codex", quotas: [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "codex")
        ], capturedAt: Date()))
        given(bProbe).probe().willThrow(ProbeError.authenticationRequired)
        let a = CodexProvider(probe: aProbe, settingsRepository: settings,
            account: ProviderAccount(accountId: "a", providerId: "codex", label: "", email: "a@example.com"))
        let b = CodexProvider(probe: bProbe, settingsRepository: settings,
            account: ProviderAccount(accountId: "b", providerId: "codex", label: "", email: "b@example.com"))
        let snapshot = try await a.refresh()
        await #expect(throws: ProbeError.self) { try await b.refresh() }
        #expect(a.id == "codex.a")
        #expect(b.id == "codex.b")
        #expect(a.name == "a@example.com")
        #expect(b.name == "b@example.com")
        #expect(snapshot.providerId == a.id)
        #expect(snapshot.quotas.first?.providerId == a.id)
        #expect(a.snapshot?.lowestQuota?.percentRemaining == 80)
        #expect(a.lastError == nil)
        #expect(b.snapshot == nil)
        #expect(b.lastError != nil)
    }
}

@Suite("Codex menu bar email labels")
struct CodexAccountLabelTests {
    @Test func `short addresses remain intact`() {
        #expect(CodexAccountLabel.compact("a@example.com", among: ["a@example.com"]) == "a@example.com")
    }

    @Test func `abbreviated collisions retain full emails`() {
        let emails = ["same-long-prefix-one@example.com", "same-long-prefix-two@example.com"]
        for email in emails {
            #expect(CodexAccountLabel.compact(email, among: emails) == email)
        }
    }
}

@Suite("Codex overlapping refreshes")
@MainActor
struct CodexOverlappingRefreshTests {
    @Test func `overlapping refreshes share one account result`() async throws {
        let settings = MockProviderSettingsRepository()
        given(settings).isEnabled(forProvider: .any).willReturn(true)
        let probe = SuspendedCodexProbe()
        let provider = CodexProvider(probe: probe, settingsRepository: settings)
        let first = Task { try await provider.refresh() }
        await probe.waitUntilStarted()
        let started = RefreshStartedFlag()
        let second = Task {
            started.value = true
            return try await provider.refresh()
        }
        while !started.value { await Task.yield() }
        await probe.finish()
        let firstResult = try await first.value
        let secondResult = try await second.value
        #expect(firstResult.lowestQuota?.percentRemaining == 80)
        #expect(secondResult == firstResult)
        #expect(provider.snapshot == firstResult)
        #expect(!provider.isSyncing)
    }
}

@MainActor private final class RefreshStartedFlag { var value = false }

private actor SuspendedCodexProbe: UsageProbe {
    private var started = false
    private var continuation: CheckedContinuation<UsageSnapshot, Never>?
    func isAvailable() async -> Bool { true }
    func probe() async throws -> UsageSnapshot {
        if started { return snapshot(remaining: 10) }
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }
    func finish() {
        continuation?.resume(returning: snapshot(remaining: 80))
        continuation = nil
    }
    private func snapshot(remaining: Double) -> UsageSnapshot {
        UsageSnapshot(providerId: "codex", quotas: [
            UsageQuota(percentRemaining: remaining, quotaType: .session, providerId: "codex")
        ], capturedAt: Date())
    }
}
