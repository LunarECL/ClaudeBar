import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct CodexUsageProbeTests {

    @Test
    func `isAvailable returns true when client finds binary`() async {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).isAvailable().willReturn(true)
        let probe = CodexUsageProbe(client: mockClient)

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when client cannot find binary`() async {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).isAvailable().willReturn(false)
        let probe = CodexUsageProbe(client: mockClient)

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `stripANSICodes removes colors`() {
        let input = "\u{1B}[32mGreen\u{1B}[0m Text"
        #expect(CodexUsageProbe.stripANSICodes(input) == "Green Text")
    }

    @Test
    func `extractUsageError finds common errors`() {
        #expect(CodexUsageProbe.extractUsageError("data not available yet") != nil)
        #expect(CodexUsageProbe.extractUsageError("Update available: 1.2.1 ... codex") == .updateRequired)
        #expect(CodexUsageProbe.extractUsageError("All good") == nil)
    }
}

// MARK: - Probe Tests

@Suite
struct CodexUsageProbeRPCTests {

    /// Temp home directory with (or without) a fake `~/.codex/auth.json`.
    private func makeTempHome(withAuth: Bool) -> (CodexCredentialLoader, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-codex-probe-\(UUID().uuidString)")
        let codexDir = dir.appendingPathComponent(".codex")
        try? FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        if withAuth {
            let auth = codexDir.appendingPathComponent("auth.json")
            try? Data("{\"tokens\":{\"access_token\":\"test-token\"}}".utf8).write(to: auth)
        }
        return (CodexCredentialLoader(homeDirectory: dir.path), dir)
    }

    /// Hand-written client double: records fetches as state so tests can
    /// assert the CLI was never spawned without Mockable failure diagnostics.
    private final class CountingRPCClient: CodexRPCClient, @unchecked Sendable {
        private let lock = NSLock()
        private var _fetchCalls = 0
        private var _shutdownCalls = 0

        var fetchCalls: Int { lock.withLock { _fetchCalls } }
        var shutdownCalls: Int { lock.withLock { _shutdownCalls } }

        func isAvailable() -> Bool { true }

        func fetchRateLimits() async throws -> CodexRateLimitsResponse {
            lock.withLock { _fetchCalls += 1 }
            return CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 30, resetDescription: nil),
                secondary: nil
            )
        }

        func shutdown() {
            lock.withLock { _shutdownCalls += 1 }
        }
    }

    @Test
    func `probe refuses to spawn the CLI when auth json is missing`() async {
        let (loader, dir) = makeTempHome(withAuth: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = CountingRPCClient()
        let probe = CodexUsageProbe(client: client, credentialLoader: loader)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }

        // No auth file means the CLI could open the browser login when
        // spawned — the probe must not launch it at all (issue #216)
        #expect(client.fetchCalls == 0)
    }

    @Test
    func `probe fetches rate limits when auth json exists`() async throws {
        let (loader, dir) = makeTempHome(withAuth: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = CountingRPCClient()
        let probe = CodexUsageProbe(client: client, credentialLoader: loader)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "codex")
        #expect(snapshot.sessionQuota?.percentRemaining == 70)
        #expect(client.fetchCalls == 1)
        #expect(client.shutdownCalls == 1)
    }

    @Test
    func `probe returns snapshot from client`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 30, resetDescription: "Resets in 2h"),
                secondary: CodexRateLimitWindow(usedPercent: 50, resetDescription: "Resets in 3d"),
                planType: "pro"
            )
        )
        given(mockClient).shutdown().willReturn(())

        let (loader, dir) = makeTempHome(withAuth: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let probe = CodexUsageProbe(client: mockClient, credentialLoader: loader)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.providerId == "codex")
        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.sessionQuota?.percentRemaining == 70) // 100 - 30
        #expect(snapshot.weeklyQuota?.percentRemaining == 50) // 100 - 50
    }

    @Test
    func `probe returns only primary quota when secondary is nil`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 25, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let (loader, dir) = makeTempHome(withAuth: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let probe = CodexUsageProbe(client: mockClient, credentialLoader: loader)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 75)
        #expect(snapshot.weeklyQuota == nil)
    }

    @Test
    func `probe handles free plan with zero usage`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 0, resetDescription: "Free plan"),
                secondary: nil,
                planType: "free"
            )
        )
        given(mockClient).shutdown().willReturn(())

        let (loader, dir) = makeTempHome(withAuth: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let probe = CodexUsageProbe(client: mockClient, credentialLoader: loader)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 100)
    }

    @Test
    func `probe clamps negative percent remaining to zero`() async throws {
        // Given - usage over 100%
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 110, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let (loader, dir) = makeTempHome(withAuth: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let probe = CodexUsageProbe(client: mockClient, credentialLoader: loader)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 0) // max(0, 100-110)
    }

    @Test
    func `probe shuts down client after fetch`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 50, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let (loader, dir) = makeTempHome(withAuth: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let probe = CodexUsageProbe(client: mockClient, credentialLoader: loader)

        // When
        _ = try await probe.probe()

        // Then - verify shutdown was called
        verify(mockClient).shutdown().called(.atLeastOnce)
    }
}

// MARK: - Mapping Tests

@Suite
struct CodexRateLimitsToSnapshotMappingTests {

    @Test
    func `maps primary window to session quota`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 40, resetDescription: "Resets in 1h"),
            secondary: nil
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 60)
        #expect(snapshot.sessionQuota?.resetText == "Resets in 1h")
    }

    @Test
    func `maps secondary window to weekly quota`() throws {
        let response = CodexRateLimitsResponse(
            primary: nil,
            secondary: CodexRateLimitWindow(usedPercent: 20, resetDescription: "Resets in 5d")
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.weeklyQuota?.percentRemaining == 80)
        #expect(snapshot.weeklyQuota?.resetText == "Resets in 5d")
    }

    @Test
    func `maps both windows to quotas`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 30, resetDescription: nil),
            secondary: CodexRateLimitWindow(usedPercent: 60, resetDescription: nil)
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.sessionQuota?.percentRemaining == 70)
        #expect(snapshot.weeklyQuota?.percentRemaining == 40)
    }

    @Test
    func `carries reset dates through to quotas`() throws {
        let sessionReset = Date().addingTimeInterval(2 * 3600)
        let weeklyReset = Date().addingTimeInterval(3 * 86400)
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 30, resetDescription: "Resets in 2h", resetsAt: sessionReset),
            secondary: CodexRateLimitWindow(usedPercent: 60, resetDescription: "Resets in 3d", resetsAt: weeklyReset)
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.sessionQuota?.resetsAt == sessionReset)
        #expect(snapshot.weeklyQuota?.resetsAt == weeklyReset)
        #expect(snapshot.sessionQuota?.resetText == "Resets in 2h")
        #expect(snapshot.sessionQuota?.compactResetTime != nil)
        #expect(snapshot.weeklyQuota?.compactResetTime != nil)
    }

    @Test
    func `carries window duration through to quotas`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 94, resetDescription: nil, resetsAt: nil, windowDuration: 7 * 24 * 3600),
            secondary: nil
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.sessionQuota?.windowDuration == TimeInterval(7 * 24 * 3600))
    }

    @Test
    func `throws when no rate limits found`() throws {
        let response = CodexRateLimitsResponse(primary: nil, secondary: nil)

        #expect(throws: ProbeError.self) {
            try CodexUsageProbe.mapRateLimitsToSnapshot(response)
        }
    }

    @Test
    func `sets provider id to codex`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 0, resetDescription: nil),
            secondary: nil
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.providerId == "codex")
    }
}
