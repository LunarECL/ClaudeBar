import Testing
import Foundation
import Mockable
import os
@testable import Infrastructure
@testable import Domain

@Suite
struct ClaudeUsageProbeTests {

    @Test
    func `isAvailable returns true when CLI executor finds binary`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when CLI executor cannot find binary`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn(nil)
        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Probe session marking (issue #222)

    @Test
    func `probe marks its claude sessions with the probe environment marker`() {
        #expect(ClaudeUsageProbe.probeEnvironment[HookConstants.probeEnvironmentKey] == "1")
    }

    // MARK: - Date Parsing Tests

    @Test
    func `parses reset date with days hours and minutes`() {
        let probe = ClaudeUsageProbe()
        let now = Date()
        
        // Days
        let d2 = probe.parseResetDate("resets in 2d")
        #expect(d2 != nil)
        #expect(d2!.timeIntervalSince(now) > 2 * 23 * 3600) // approx 2 days
        
        // Hours and minutes
        let hm = probe.parseResetDate("resets in 2h 15m")
        #expect(hm != nil)
        let diff = hm!.timeIntervalSince(now)
        #expect(diff > 2 * 3600 + 14 * 60)
        #expect(diff < 2 * 3600 + 16 * 60)
        
        // Just minutes
        let m30 = probe.parseResetDate("30m")
        #expect(m30 != nil)
        #expect(m30!.timeIntervalSince(now) > 29 * 60)
    }

    @Test
    func `parseResetDate returns nil for invalid input`() {
        let probe = ClaudeUsageProbe()
        #expect(probe.parseResetDate(nil) == nil)
        #expect(probe.parseResetDate("") == nil)
        #expect(probe.parseResetDate("no time here") == nil)
    }

    // MARK: - Absolute Time Parsing Tests

    @Test
    func `parses reset date with time only and timezone`() {
        let probe = ClaudeUsageProbe()

        // "Resets 4:59pm (America/New_York)" — should resolve to a Date today or tomorrow
        let result = probe.parseResetDate("Resets 4:59pm (America/New_York)")
        #expect(result != nil, "Should parse time-only format with timezone")
        if let date = result {
            // Should be within the next 24 hours
            let diff = date.timeIntervalSinceNow
            #expect(diff > -60) // Allow small margin for test execution
            #expect(diff < 24 * 3600 + 60)
        }
    }

    @Test
    func `parses reset date with short time and timezone`() {
        let probe = ClaudeUsageProbe()

        // "Resets 3pm (Asia/Shanghai)" — short time without minutes
        let result = probe.parseResetDate("Resets 3pm (Asia/Shanghai)")
        #expect(result != nil, "Should parse short time format like 3pm")
    }

    @Test
    func `parses reset date with month day and time with timezone`() {
        let probe = ClaudeUsageProbe()

        // "Resets Dec 25 at 4:59am (Asia/Shanghai)"
        let result = probe.parseResetDate("Resets Dec 25 at 4:59am (Asia/Shanghai)")
        #expect(result != nil, "Should parse 'Mon DD at H:MMam (TZ)' format")
    }

    @Test
    func `parses reset date with month day comma time and timezone`() {
        let probe = ClaudeUsageProbe()

        // "Resets Jan 15, 3:30pm (America/Los_Angeles)"
        let result = probe.parseResetDate("Resets Jan 15, 3:30pm (America/Los_Angeles)")
        #expect(result != nil, "Should parse 'Mon DD, H:MMpm (TZ)' format")
    }

    @Test
    func `parses reset date with month day comma time without timezone`() {
        let probe = ClaudeUsageProbe()

        // "Resets Jan 15, 3:30pm"
        let result = probe.parseResetDate("Resets Jan 15, 3:30pm")
        #expect(result != nil, "Should parse 'Mon DD, H:MMpm' without timezone")
    }

    @Test
    func `parses reset date with month day year and timezone`() {
        let probe = ClaudeUsageProbe()

        // Always use a future year so the test never goes stale
        let futureYear = Calendar.current.component(.year, from: Date()) + 1
        let result = probe.parseResetDate("Resets Jan 1, \(futureYear) (America/New_York)")
        #expect(result != nil, "Should parse 'Mon DD, YYYY (TZ)' format")
    }

    @Test
    func `parses reset date with month day only`() {
        let probe = ClaudeUsageProbe()

        // "Resets Dec 28"
        let result = probe.parseResetDate("Resets Dec 28")
        #expect(result != nil, "Should parse 'Mon DD' date-only format")
    }

    @Test
    func `parsed absolute date has correct timezone`() {
        let probe = ClaudeUsageProbe()

        // Two calls with different timezones for the same time should yield different Dates
        let eastern = probe.parseResetDate("Resets 4:59pm (America/New_York)")
        let shanghai = probe.parseResetDate("Resets 4:59pm (Asia/Shanghai)")
        #expect(eastern != nil)
        #expect(shanghai != nil)
        if let e = eastern, let s = shanghai {
            // These should NOT be equal — different timezones for the same wall-clock time
            #expect(e != s, "Same wall-clock time in different timezones should produce different Dates")
        }
    }

    // MARK: - Helper Tests

    @Test
    func `cleanResetText adds resets prefix if missing`() {
        let probe = ClaudeUsageProbe()
        #expect(probe.cleanResetText("in 2h") == "Resets in 2h")
        #expect(probe.cleanResetText("Resets in 2h") == "Resets in 2h")
        #expect(probe.cleanResetText(nil) == nil)
    }

    @Test
    func `extractEmail finds email in various formats`() {
        let probe = ClaudeUsageProbe()
        // Old format
        #expect(probe.extractEmail(text: "Account: user@example.com") == "user@example.com")
        #expect(probe.extractEmail(text: "Email: user@example.com") == "user@example.com")
        // Header format
        #expect(probe.extractEmail(text: "Opus 4.5 · Claude Max · user@example.com's Organization") == "user@example.com")
        #expect(probe.extractEmail(text: "Opus 4.5 · Claude Pro · test@test.com's Org") == "test@test.com")
        // No email
        #expect(probe.extractEmail(text: "No email here") == nil)
        #expect(probe.extractEmail(text: "Opus 4.5 · Claude Pro · Organization") == nil)
    }

    @Test
    func `extractOrganization finds org`() {
        let probe = ClaudeUsageProbe()
        // Old format
        #expect(probe.extractOrganization(text: "Organization: Acme Corp") == "Acme Corp")
        #expect(probe.extractOrganization(text: "Org: Acme Corp") == "Acme Corp")
        // Header format with email
        #expect(probe.extractOrganization(text: "Opus 4.5 · Claude Max · user@example.com's Organization") == "user@example.com's Organization")
        // Header format without email - just company name
        #expect(probe.extractOrganization(text: "Opus 4.5 · Claude Pro · My Company") == "My Company")
        // Header format with just a person's name
        #expect(probe.extractOrganization(text: "Opus 4.5 · Claude Pro · Vincent Young") == "Vincent Young")
    }

    @Test
    func `extractLoginMethod finds method`() {
        let probe = ClaudeUsageProbe()
        #expect(probe.extractLoginMethod(text: "Login method: Claude Max") == "Claude Max")
    }

    @Test
    func `extractFolderFromTrustPrompt finds path`() {
        let probe = ClaudeUsageProbe()
        let output = "Do you trust the files in this folder?\n/Users/test/project\n\nYes/No"
        #expect(probe.extractFolderFromTrustPrompt(output) == "/Users/test/project")
    }

    @Test
    func `probeWorkingDirectory creates and returns URL`() {
        let probe = ClaudeUsageProbe()
        let url = probe.probeWorkingDirectory()
        #expect(url.path.contains("ClaudeBar/Probe"))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Probe Tests

    @Test
    func `probe extracts account type from usage output`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()

        // /usage returns Max account with quota data
        let usageOutput = """
        Opus 4.5 · Claude Max · user@example.com's Organization

        Current session
        ████████████████░░░░ 65% left
        Resets in 2h 15m

        Current week (all models)
        ██████████░░░░░░░░░░ 35% left
        Resets Dec 28
        """

        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/usage" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: usageOutput, exitCode: 0))

        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.accountTier == .claudeMax)
        #expect(snapshot.quotas.count >= 1)
    }

    @Test
    func `probe extracts Pro account with Extra usage`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()

        let usageOutput = """
        Opus 4.5 · Claude Pro · user@example.com's Organization

        Current session
        █████░░░░░░░░░░░░░░░ 1% used
        Resets 4:59pm (America/New_York)

        Current week (all models)
        █████████████████░░░ 36% used
        Resets Dec 25 at 2:59pm (America/New_York)

        Extra usage
        █████░░░░░░░░░░░░░░░ 27% used
        $5.41 / $20.00 spent · Resets Jan 1, 2026 (America/New_York)
        """

        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/usage" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: usageOutput, exitCode: 0))

        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.costUsage != nil)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(snapshot.costUsage?.budget == Decimal(string: "20.00"))
        #expect(snapshot.costUsage?.kind == .extraUsage)
        #expect(snapshot.quotas.count >= 1)
    }

    @Test
    func `probe falls back to cost when usage renders the API billing panel`() async throws {
        // Given — issue #271: the Usage tab paints a cost panel with no quota bars
        let mockExecutor = MockCLIExecutor()

        let usageOutput = """
        Opus 5 (1M context) · API Usage Billing

          Session
            Total cost:            $0.0000
            Total duration (API):  0s
            Usage:                 0 input, 0 output, 0 cache read, 0 cache write
        """

        let costOutput = """
        Total cost:            $1.25
        Total duration (API):  6m 19.7s
        Total duration (wall): 1h 2m
        """

        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/usage" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: usageOutput, exitCode: 0))

        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/cost" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: costOutput, exitCode: 0))

        // A genuine pay-as-you-go account: nothing in the config claims a
        // subscription, so the cost panel is the truth and /cost answers it.
        let resolver = MockAccountInfoResolving()
        given(resolver).resolve().willReturn(AccountInfo(email: "user@example.com", billingType: "api"))

        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor, accountInfoResolver: resolver)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "1.25"))
        #expect(snapshot.accountTier == .claudeApi)
    }

    @Test
    func `probe fails instead of costing out a subscription the CLI could not see`() async throws {
        // Given — issue #271: a Max plan billed through Apple renders the same
        // cost panel, but the config still says it is a subscription. /cost
        // would answer $0.00 with no quota, and its success would keep
        // ClaudeProvider from trying the usage API, which can still read the
        // real numbers. So the probe fails and lets that fallback run.
        let mockExecutor = MockCLIExecutor()

        let usageOutput = """
        Opus 5 (1M context) · API Usage Billing

          Session
            Total cost:            $0.0000
            Total duration (API):  0s
            Usage:                 0 input, 0 output, 0 cache read, 0 cache write
        """

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: usageOutput, exitCode: 0))

        let resolver = MockAccountInfoResolving()
        given(resolver).resolve().willReturn(
            AccountInfo(email: "user@example.com", billingType: "apple_subscription")
        )

        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor, accountInfoResolver: resolver)

        // When / Then
        await #expect(throws: ProbeError.executionFailed(ClaudeUsageProbe.subscriptionMisreadAsApiBilling)) {
            try await probe.probe()
        }
    }

    // MARK: - Account Info from ClaudeAccountInfoResolver

    @Test
    func `probe resolves account info from config file`() async throws {
        // Given - new tabbed CLI output (no account info in /usage tab)
        let mockExecutor = MockCLIExecutor()

        let tabbedUsageOutput = """
          Status   Config   Usage

        Current session
        ▌                                                  1% used
        Resets 12am (Asia/Shanghai)

        Current week (all models)
        ██████████████████████▌                            45% used
        Resets 10:59am (Asia/Shanghai)

        Extra usage
        Extra usage not enabled • /extra-usage to enable

        Esc to cancel
        """

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/usage" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: tabbedUsageOutput, exitCode: 0))

        // Mock resolver returns account info
        let mockResolver = MockAccountInfoResolving()
        given(mockResolver).resolve().willReturn(AccountInfo(email: "user@example.com", organization: "testuser"))

        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor, accountInfoResolver: mockResolver)

        // When
        let snapshot = try await probe.probe()

        // Then - account info from config, tier from CLI output
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountOrganization == "testuser")
        #expect(snapshot.quotas.count >= 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 99)
    }

    // MARK: - Setup Token Environment Exclusion Tests

    @Test
    func `envExclusions includes CLAUDE_CODE_OAUTH_TOKEN`() {
        // The CLI probe must strip the setup-token env var so that
        // `claude /usage` falls back to stored credentials with full scope.
        #expect(ClaudeUsageProbe.envExclusions.contains("CLAUDE_CODE_OAUTH_TOKEN"))
    }

    @Test
    func `default init creates executor that excludes setup token env var`() {
        // When ClaudeUsageProbe is created without an explicit CLIExecutor,
        // the default executor should be configured to exclude CLAUDE_CODE_OAUTH_TOKEN.
        // We verify this indirectly by checking the static envExclusions constant.
        let exclusions = ClaudeUsageProbe.envExclusions
        #expect(exclusions == ["CLAUDE_CODE_OAUTH_TOKEN"])
    }

    // MARK: - Completion Rule Pairing (issue #317)

    @Test
    func `the cost fallback runs with no completion rule so it ends on idle`() {
        // The regression #317 introduced: both commands shared one executor
        // carrying `.claudeUsage`. Its markers are quota-bar markers, and an
        // API-billed account never paints a quota bar, so `isPending` stayed true
        // for the whole run, the idle break could never fire, and every `/cost`
        // capture burned the full 20s timeout instead of the ~3.7s it takes with
        // no rule (measured against the real InteractiveRunner).
        //
        // The pairing is the point, not just the values: a rule is not "the
        // right markers", it is "markers this screen can actually reach".
        let probe = ClaudeUsageProbe()

        let usageRule = (probe.cliExecutor as? DefaultCLIExecutor)?.completionRule
        let costRule = (probe.costExecutor as? DefaultCLIExecutor)?.completionRule
        #expect(usageRule == CLICompletionRule.claudeUsage)
        #expect(costRule == nil)
    }

    // MARK: - Shared probe session (issue #132)

    /// A settled /usage screen with quota bars — the minimum the parser needs.
    private static let settledUsageOutput = """
    Opus 4.5 · Claude Max · user@example.com's Organization

    Current session
    ████████████████░░░░ 65% left
    Resets in 2h 15m

    Current week (all models)
    ██████████░░░░░░░░░░ 35% left
    Resets Dec 28
    """

    /// An API-billing /usage panel: no quota bars, routes the probe to /cost (#271).
    private static let apiBillingUsageOutput = """
    Opus 5 (1M context) · API Usage Billing

      Session
        Total cost:            $0.0000
        Total duration (API):  0s
        Usage:                 0 input, 0 output, 0 cache read, 0 cache write
    """

    private static func sessionFlagValue(in args: [String], flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// Records every execute() call so tests can assert the args the probe
    /// actually sent (Chicago school: resulting state, no verify()).
    private final class RecordingCLIExecutor: CLIExecutor, @unchecked Sendable {
        struct Call: Equatable {
            let binary: String
            let args: [String]
            let input: String?
        }

        private let calls = OSAllocatedUnfairLock(initialState: [Call]())
        private let respond: @Sendable (Call) -> CLIResult

        init(respond: @escaping @Sendable (Call) -> CLIResult) {
            self.respond = respond
        }

        func locate(_ binary: String) -> String? {
            "/usr/bin/claude"
        }

        func execute(
            binary: String,
            args: [String],
            input: String?,
            timeout: TimeInterval,
            workingDirectory: URL?,
            autoResponses: [String: String]
        ) async throws -> CLIResult {
            let call = Call(binary: binary, args: args, input: input)
            calls.withLock { $0.append(call) }
            return respond(call)
        }

        var recordedCalls: [Call] {
            calls.withLock { $0 }
        }
    }

    /// In-memory `ProbeSessionStore` so tests never touch the real
    /// `probe-session.json` in the probe working directory.
    private final class InMemorySessionStore: ProbeSessionStore, @unchecked Sendable {
        private struct State {
            var id: String?
            var saves = 0
            var clears = 0
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        func loadSessionID() -> String? {
            state.withLock { current in current.id }
        }

        func saveSessionID(_ id: String) {
            state.withLock { current in
                current.id = id
                current.saves += 1
            }
        }

        func clearSessionID() {
            state.withLock { current in
                current.id = nil
                current.clears += 1
            }
        }

        /// Pre-loads a stored id, as if an earlier poll had created it.
        func seed(_ id: String) {
            state.withLock { current in current.id = id }
        }

        var saveCount: Int {
            state.withLock { current in current.saves }
        }
    }

    @Test
    func `the usage command creates the shared probe session on first run`() async throws {
        // Given — no stored session yet, so this run must create it under a
        // stable id and the "ClaudeBar Probe" display name (#132).
        let executor = RecordingCLIExecutor { _ in
            CLIResult(output: Self.settledUsageOutput, exitCode: 0)
        }
        let probe = ClaudeUsageProbe(cliExecutor: executor, sessionStore: InMemorySessionStore())

        // When
        _ = try await probe.probe()

        // Then
        let first = try #require(executor.recordedCalls.first)
        #expect(first.args.contains("--session-id"), "expected the /usage args \(first.args) to create a session with a stable id")
        let createdID = Self.sessionFlagValue(in: first.args, flag: "--session-id")
        #expect(createdID != nil && UUID(uuidString: createdID!) != nil)
        #expect(Self.sessionFlagValue(in: first.args, flag: "--name") == "ClaudeBar Probe")
    }

    @Test
    func `the cost fallback reuses the same shared probe session`() async throws {
        // Given — an API-billed account routes the probe through /cost; both
        // commands must bind to the same shared session (#132).
        let executor = RecordingCLIExecutor { call in
            if call.args.first == "/cost" {
                CLIResult(
                    output: """
                    Total cost:            $1.25
                    Total duration (API):  6m 19.7s
                    Total duration (wall): 1h 2m
                    """,
                    exitCode: 0
                )
            } else {
                CLIResult(output: Self.apiBillingUsageOutput, exitCode: 0)
            }
        }
        let resolver = MockAccountInfoResolving()
        given(resolver).resolve().willReturn(AccountInfo(email: "user@example.com", billingType: "api"))
        let probe = ClaudeUsageProbe(cliExecutor: executor, accountInfoResolver: resolver, sessionStore: InMemorySessionStore())

        // When
        _ = try await probe.probe()

        // Then
        let usageCall = try #require(executor.recordedCalls.first { $0.args.first == "/usage" })
        let costCall = try #require(executor.recordedCalls.first { $0.args.first == "/cost" })
        let usageID = Self.sessionFlagValue(in: usageCall.args, flag: "--session-id")
            ?? Self.sessionFlagValue(in: usageCall.args, flag: "--resume")
        let costID = Self.sessionFlagValue(in: costCall.args, flag: "--session-id")
            ?? Self.sessionFlagValue(in: costCall.args, flag: "--resume")
        #expect(usageID != nil, "expected the /usage args \(usageCall.args) to carry a session id")
        #expect(costID != nil, "expected the /cost args \(costCall.args) to carry a session id")
        #expect(usageID == costID, "usage and cost must run in the same shared session")
    }

    @Test
    func `consecutive probes resume the same shared session`() async throws {
        // Given — two polls of one probe instance must reuse the session the
        // first poll created (#132).
        let executor = RecordingCLIExecutor { _ in
            CLIResult(output: Self.settledUsageOutput, exitCode: 0)
        }
        let probe = ClaudeUsageProbe(cliExecutor: executor, sessionStore: InMemorySessionStore())

        // When
        _ = try await probe.probe()
        _ = try await probe.probe()

        // Then
        let first = try #require(executor.recordedCalls.first)
        let second = try #require(executor.recordedCalls.dropFirst().first)
        let createdID = try #require(Self.sessionFlagValue(in: first.args, flag: "--session-id"))
        let resumedID = try #require(Self.sessionFlagValue(in: second.args, flag: "--resume"), "expected the second poll to resume, got \(second.args)")
        #expect(resumedID == createdID, "both polls must use the same session id")
    }

    @Test
    func `the shared session id survives a fresh probe`() async throws {
        // Given — the id lives in the probe working directory, so a brand-new
        // probe instance (app restart) picks the session back up (#132).
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-probe-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstExecutor = RecordingCLIExecutor { _ in
            CLIResult(output: Self.settledUsageOutput, exitCode: 0)
        }
        let first = ClaudeUsageProbe(
            cliExecutor: firstExecutor,
            sessionStore: FileProbeSessionStore(directory: directory)
        )
        _ = try await first.probe()
        let firstCall = try #require(firstExecutor.recordedCalls.first)
        let createdID = try #require(Self.sessionFlagValue(in: firstCall.args, flag: "--session-id"))

        // When — a fresh probe instance over the same directory
        let secondExecutor = RecordingCLIExecutor { _ in
            CLIResult(output: Self.settledUsageOutput, exitCode: 0)
        }
        let second = ClaudeUsageProbe(
            cliExecutor: secondExecutor,
            sessionStore: FileProbeSessionStore(directory: directory)
        )
        _ = try await second.probe()

        // Then
        let secondCall = try #require(secondExecutor.recordedCalls.first)
        let resumedID = try #require(Self.sessionFlagValue(in: secondCall.args, flag: "--resume"), "expected the fresh probe to resume, got \(secondCall.args)")
        #expect(resumedID == createdID)
    }

    @Test
    func `a vanished shared session is recreated instead of failing the probe`() async throws {
        // Given — the stored id no longer exists on the CLI side (user cleared
        // ~/.claude): drop it, recreate the session, save the new id (#132).
        let executor = RecordingCLIExecutor { call in
            if call.args.contains("--resume") {
                CLIResult(output: "No conversation found with session ID: dead-session-id", exitCode: 1)
            } else {
                CLIResult(output: Self.settledUsageOutput, exitCode: 0)
            }
        }
        let store = InMemorySessionStore()
        store.seed("dead-session-id")
        let probe = ClaudeUsageProbe(cliExecutor: executor, sessionStore: store)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.quotas.count >= 1)
        let resumed = try #require(executor.recordedCalls.first { $0.args.contains("--resume") })
        #expect(resumed.args.contains("dead-session-id"))
        let recreated = try #require(executor.recordedCalls.first { $0.args.contains("--session-id") })
        #expect(Self.sessionFlagValue(in: recreated.args, flag: "--session-id") != "dead-session-id")
        #expect(store.loadSessionID() == Self.sessionFlagValue(in: recreated.args, flag: "--session-id"))
    }

    @Test
    func `an older CLI without session flags still probes like today`() async throws {
        // Given — a CLI too old for the session flags rejects them; the probe
        // must fall back to today's plain invocation and still parse (#132).
        let executor = RecordingCLIExecutor { call in
            if call.args.contains("--session-id") || call.args.contains("--resume") {
                return CLIResult(output: "error: unknown option '--session-id'", exitCode: 1)
            }
            return CLIResult(output: Self.settledUsageOutput, exitCode: 0)
        }
        let probe = ClaudeUsageProbe(cliExecutor: executor, sessionStore: InMemorySessionStore())

        // When
        let snapshot = try await probe.probe()

        // Then — the shared session was tried first, today's args second, and
        // the parse still succeeds.
        #expect(snapshot.quotas.count >= 1)
        let first = try #require(executor.recordedCalls.first)
        #expect(first.args.contains("--session-id"), "expected the probe to try the shared session first, got \(first.args)")
        let last = try #require(executor.recordedCalls.last)
        #expect(last.args == ["/usage", "--allowed-tools", ""], "expected the fallback to match today's args, got \(last.args)")
    }

    @Test
    func `an unsupported CLI skips the session flags on the next poll`() async throws {
        // Given — after one unsupported-flag run, later polls must not pay for
        // another failing attempt (#132).
        let executor = RecordingCLIExecutor { call in
            if call.args.contains("--session-id") || call.args.contains("--resume") {
                return CLIResult(output: "error: unknown option '--session-id'", exitCode: 1)
            }
            return CLIResult(output: Self.settledUsageOutput, exitCode: 0)
        }
        let probe = ClaudeUsageProbe(cliExecutor: executor, sessionStore: InMemorySessionStore())

        // When
        _ = try await probe.probe()
        let callsAfterFirstPoll = executor.recordedCalls.count
        _ = try await probe.probe()

        // Then
        let secondPollCalls = Array(executor.recordedCalls.dropFirst(callsAfterFirstPoll))
        #expect(secondPollCalls.count == 1)
        #expect(secondPollCalls.first?.args == ["/usage", "--allowed-tools", ""])
    }

    @Test
    func `session args fall back to today's invocation for plan none`() {
        // The `.none` plan must reproduce the exact args the probe has always
        // sent, so the fallback really is today's behavior (#132).
        let probe = ClaudeUsageProbe(sessionStore: InMemorySessionStore())
        #expect(probe.sessionArgs(for: .none, command: "/usage") == ["/usage", "--allowed-tools", ""])
        #expect(probe.sessionArgs(for: .none, command: "/cost") == ["/cost", "--allowed-tools", ""])
        #expect(
            probe.sessionArgs(for: .create(sessionID: "abc"), command: "/usage")
                == ["/usage", "--allowed-tools", "", "--session-id", "abc", "--name", ClaudeUsageProbe.probeSessionName]
        )
        #expect(
            probe.sessionArgs(for: .resume(sessionID: "abc"), command: "/usage")
                == ["/usage", "--allowed-tools", "", "--resume", "abc"]
        )
    }

    @Test
    func `session store roundtrips the id across fresh instances`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-probe-session-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileProbeSessionStore(directory: directory)
        #expect(store.loadSessionID() == nil)

        store.saveSessionID("abc-123")
        #expect(FileProbeSessionStore(directory: directory).loadSessionID() == "abc-123")

        store.clearSessionID()
        #expect(FileProbeSessionStore(directory: directory).loadSessionID() == nil)
    }

    @Test
    func `unsupported flag and missing session errors are recognized`() {
        #expect(ClaudeUsageProbe.isUnsupportedFlagError("error: unknown option '--session-id'"))
        #expect(ClaudeUsageProbe.isUnsupportedFlagError("error: unexpected argument '--name'"))
        #expect(!ClaudeUsageProbe.isUnsupportedFlagError(Self.settledUsageOutput))
        #expect(ClaudeUsageProbe.isSessionNotFoundError("No conversation found with session ID: abc"))
        #expect(ClaudeUsageProbe.isSessionNotFoundError("No session found for name: abc"))
        #expect(!ClaudeUsageProbe.isSessionNotFoundError(Self.settledUsageOutput))
    }
}
