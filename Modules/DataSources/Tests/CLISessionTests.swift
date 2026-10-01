import Quotas
import Foundation
import Mockable
import Testing
@testable import DataSources

/// One session shared by every run of a CLI call (#132).
///
/// The definition carries the session contract as data — where the id is kept,
/// the args that create and resume the session, the output that says the stored
/// session is gone, and the output that says this CLI build rejects the flags —
/// and the fetcher runs the plan: create once, resume after, recreate when
/// gone, fall back to the plain invocation when the flags are refused.
@Suite("Session reuse on a CLI call (#132)")
struct CLISessionTests {

    // MARK: - Helpers

    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// Thread-safe recorder of every `execute` run's args, in order.
    private final class Launches: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [[String]] = []
        func record(_ args: [String]) { lock.withLock { all.append(args) } }
        var recorded: [[String]] { lock.withLock { all } }
    }

    private func call(
        args: [String] = ["/usage", "--allowed-tools", ""],
        session: SessionReuse,
        workingDirectory: WorkingDirectory? = nil
    ) -> CLICall {
        CLICall(cli: "claude", args: args, timeout: 20, workingDirectory: workingDirectory, session: session)
    }

    /// Thread-safe queue of ids the runner hands out, in order.
    private final class IDQueue: @unchecked Sendable {
        private let lock = NSLock()
        private let ids: [String]
        private var index = 0
        init(_ ids: [String]) { self.ids = ids }
        func next() -> String {
            lock.withLock {
                defer { index += 1 }
                guard index < ids.count else { return "unexpected-id-\(index)" }
                return ids[index]
            }
        }
    }

    private func runner(
        _ call: CLICall,
        executor: MockCLIExecutor,
        launches: Launches? = nil,
        ids: [String] = [],
        fileURL: URL? = nil,
        latch: SessionFlagLatch = SessionFlagLatch()
    ) -> CLISessionRunner {
        let queue = IDQueue(ids)
        let url = fileURL ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-tests-\(UUID().uuidString)")
            .appendingPathComponent("probe-session.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return CLISessionRunner(
            call: call,
            reuse: call.session ?? session(),
            directory: nil,
            makeExecutor: { _ in executor },
            fileURL: url,
            latch: latch,
            nextID: { queue.next() }
        )
    }

    private func screen(_ text: String, exitCode: Int32 = 0, executor: MockCLIExecutor, launches: Launches) {
        given(executor).locate(.any).willReturn("/usr/local/bin/claude")
        given(executor).execute(
            binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any
        ).willProduce { @Sendable _, args, _, _, _, _ in
            launches.record(args)
            return CLIResult(output: text, exitCode: exitCode)
        }
    }

    private let usageScreen = """
    Current session
    ████████████████░░░░ 65% left
    Resets in 2h 15m
    """

    private func session(file: String = "/probe-session.json") -> SessionReuse {
        SessionReuse(
            file: file,
            create: ["--session-id", "{{id}}", "--name", "ClaudeBar Probe"],
            resume: ["--resume", "{{id}}"],
            recreateOn: ["no conversation found", "no session found"],
            unsupportedOn: ["unknown option '--session-id'", "unknown option '--resume'", "unknown option '--name'"]
        )
    }

    // MARK: - The definition side

    @Test
    func `a session block decodes with its templates and tokens`() throws {
        let call = try JSONDecoder().decode(CLICall.self, from: Data("""
        {"cli":"claude","args":["/usage"],
         "session":{"file":"probe-session.json",
                    "create":["--session-id","{{id}}","--name","ClaudeBar Probe"],
                    "resume":["--resume","{{id}}"],
                    "recreateOn":["no conversation found"],
                    "unsupportedOn":["unknown option '--session-id'"]}}
        """.utf8))

        let session = try #require(call.session)
        #expect(session.file == "probe-session.json")
        #expect(session.create == ["--session-id", "{{id}}", "--name", "ClaudeBar Probe"])
        #expect(session.resume == ["--resume", "{{id}}"])
        #expect(session.recreateOn == ["no conversation found"])
        #expect(session.unsupportedOn == ["unknown option '--session-id'"])
    }

    @Test
    func `the match lists default to empty`() throws {
        let call = try JSONDecoder().decode(CLICall.self, from: Data("""
        {"cli":"claude","session":{"file":"probe-session.json","create":["--session-id","{{id}}"],"resume":["--resume","{{id}}"]}}
        """.utf8))
        #expect(call.session?.recreateOn.isEmpty == true)
        #expect(call.session?.unsupportedOn.isEmpty == true)
    }

    @Test
    func `a call without a session block encodes none`() throws {
        let call = CLICall(cli: "claude", args: ["/usage"])
        let json = String(data: try JSONEncoder().encode(call), encoding: .utf8)!

        #expect(json.contains("session") == false)
        #expect(try JSONDecoder().decode(CLICall.self, from: Data(json.utf8)) == call)
    }

    @Test
    func `a call with a session block survives the round trip`() throws {
        let call = call(session: session())
        let again = try JSONDecoder().decode(CLICall.self, from: JSONEncoder().encode(call))

        #expect(again == call)
    }

    // MARK: - The plan loop

    @Test
    func `the first run creates the session, names it, and remembers its id`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        screen(usageScreen, executor: executor, launches: launches)
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-\(UUID().uuidString)/probe-session.json")
        let runner = self.runner(
            call(session: session()),
            executor: executor,
            ids: ["11111111-2222-3333-4444-555555555555"],
            fileURL: fileURL
        )

        let result = try await runner.run()

        #expect(result.output == usageScreen)
        #expect(launches.recorded.count == 1)
        #expect(launches.recorded[0] == ["/usage", "--allowed-tools", "", "--session-id", "11111111-2222-3333-4444-555555555555", "--name", "ClaudeBar Probe"])
        #expect(CLISessionFile(url: fileURL).load() == "11111111-2222-3333-4444-555555555555")
    }

    @Test
    func `the next run resumes the stored session`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        screen(usageScreen, executor: executor, launches: launches)
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-\(UUID().uuidString)/probe-session.json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = CLISessionFile(url: fileURL)
        store.save("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let runner = self.runner(call(session: session()), executor: executor, fileURL: fileURL)

        _ = try await runner.run()
        _ = try await runner.run()

        #expect(launches.recorded.count == 2)
        #expect(launches.recorded[0] == ["/usage", "--allowed-tools", "", "--resume", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"])
        #expect(launches.recorded[1] == ["/usage", "--allowed-tools", "", "--resume", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"])
        #expect(store.load() == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    }

    @Test
    func `a vanished session is recreated under a fresh id`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        let gone = "No conversation found with session ID aaaaaaaaaa"
        given(executor).execute(
            binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any
        ).willProduce { @Sendable _, args, _, _, _, _ in
            launches.record(args)
            return CLIResult(output: args.contains("--resume") ? gone : usageScreen, exitCode: 0)
        }
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-\(UUID().uuidString)/probe-session.json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = CLISessionFile(url: fileURL)
        store.save("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let runner = self.runner(
            call(session: session()),
            executor: executor,
            ids: ["11111111-2222-3333-4444-555555555555"],
            fileURL: fileURL
        )

        let result = try await runner.run()

        #expect(result.output == usageScreen)
        #expect(launches.recorded.count == 2)
        #expect(launches.recorded[0].contains("--resume"))
        #expect(launches.recorded[1] == ["/usage", "--allowed-tools", "", "--session-id", "11111111-2222-3333-4444-555555555555", "--name", "ClaudeBar Probe"])
        #expect(store.load() == "11111111-2222-3333-4444-555555555555")
    }

    @Test
    func `a CLI that rejects the flags falls back to the plain run for good`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        let refused = "error: unknown option '--session-id'"
        given(executor).execute(
            binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any
        ).willProduce { @Sendable _, args, _, _, _, _ in
            launches.record(args)
            return CLIResult(output: args.contains("--session-id") || args.contains("--resume") ? refused : usageScreen, exitCode: 1)
        }
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-\(UUID().uuidString)/probe-session.json")
        let runner = self.runner(call(session: session()), executor: executor, ids: ["11111111-2222-3333-4444-555555555555"], fileURL: fileURL)

        let first = try await runner.run()
        let second = try await runner.run()

        #expect(first.output == usageScreen)
        #expect(second.output == usageScreen)
        // Create refused → plain retry; the latch keeps every later run plain.
        #expect(launches.recorded.count == 3)
        #expect(launches.recorded[0].contains("--session-id"))
        #expect(launches.recorded[1] == ["/usage", "--allowed-tools", ""])
        #expect(launches.recorded[2] == ["/usage", "--allowed-tools", ""])
        #expect(CLISessionFile(url: fileURL).load() == nil)
    }

    @Test
    func `a refusal while resuming also falls back, and drops the stale id`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        let refused = "error: unknown option '--resume'"
        given(executor).execute(
            binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any
        ).willProduce { @Sendable _, args, _, _, _, _ in
            launches.record(args)
            return CLIResult(output: args.contains("--resume") ? refused : usageScreen, exitCode: 1)
        }
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-\(UUID().uuidString)/probe-session.json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = CLISessionFile(url: fileURL)
        store.save("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let runner = self.runner(call(session: session()), executor: executor, fileURL: fileURL)

        _ = try await runner.run()

        #expect(launches.recorded.count == 2)
        #expect(launches.recorded[0].contains("--resume"))
        #expect(launches.recorded[1] == ["/usage", "--allowed-tools", ""])
        #expect(store.load() == nil)
    }

    @Test
    func `an unknown-option phrase on a successful screen is not a refusal`() async throws {
        // A SessionStart hook or transcript can carry the words; only a failed
        // run proves the CLI build rejects the flags.
        let launches = Launches()
        let executor = MockCLIExecutor()
        let chatty = """
        Tip: passing an unknown option '--session-id' used to error out.
        \(usageScreen)
        """
        screen(chatty, executor: executor, launches: launches)
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-\(UUID().uuidString)/probe-session.json")
        let runner = self.runner(
            call(session: session()),
            executor: executor,
            ids: ["11111111-2222-3333-4444-555555555555"],
            fileURL: fileURL
        )

        _ = try await runner.run()

        #expect(launches.recorded.count == 1)
        #expect(launches.recorded[0].contains("--session-id"))
        #expect(CLISessionFile(url: fileURL).load() == "11111111-2222-3333-4444-555555555555")
    }

    // MARK: - The detection rules

    @Test
    func `a refusal needs a non-zero exit and a token`() {
        let refused = CLIResult(output: "error: unknown option '--session-id'", exitCode: 1)

        #expect(CLISessionRunner.isRefused(refused, tokens: session().unsupportedOn))
        #expect(CLISessionRunner.isRefused(CLIResult(output: "error: unknown option '--session-id'", exitCode: 0), tokens: session().unsupportedOn) == false)
        #expect(CLISessionRunner.isRefused(CLIResult(output: "boom", exitCode: 1), tokens: session().unsupportedOn) == false)
        #expect(CLISessionRunner.isRefused(refused, tokens: []) == false)
    }

    @Test
    func `a refusal matches the token case-insensitively`() {
        let refused = CLIResult(output: "ERROR: UNKNOWN OPTION '--session-id'", exitCode: 1)

        #expect(CLISessionRunner.isRefused(refused, tokens: ["unknown option '--session-id'"]))
    }

    @Test
    func `gone tokens match case-insensitively`() {
        #expect(CLISessionRunner.isGone("No Conversation Found With Session ID x", tokens: ["no conversation found"]))
        #expect(CLISessionRunner.isGone("all good", tokens: ["no conversation found"]) == false)
        #expect(CLISessionRunner.isGone("all good", tokens: []) == false)
    }

    // MARK: - The file

    @Test
    func `the id round-trips through the file`() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = CLISessionFile(url: directory.appendingPathComponent("probe-session.json"))

        #expect(store.load() == nil)
        store.save("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(store.load() == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        store.clear()
        #expect(store.load() == nil)
    }

    @Test
    func `an empty or corrupt file reads as no session`() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("probe-session.json")

        try Data("".utf8).write(to: url)
        #expect(CLISessionFile(url: url).load() == nil)
        try Data("not json".utf8).write(to: url)
        #expect(CLISessionFile(url: url).load() == nil)
        try Data(#"{"sessionID":"""#.utf8).write(to: url)
        #expect(CLISessionFile(url: url).load() == nil)
    }

    @Test
    func `a save or read over an unwritable path does not throw`() throws {
        // The file exists but its directory refuses changes: every IO fails.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("probe-session.json")
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = CLISessionFile(url: url)

        store.save("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(store.load() == nil)
        store.clear()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - The flag latch

    @Test
    func `the latch starts supported and drops once under concurrency`() async {
        let latch = SessionFlagLatch()
        #expect(await latch.isSupported)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask { await latch.refuse() }
            }
        }

        #expect(await latch.isSupported == false)
        await latch.refuse()
        #expect(await latch.isSupported == false)
    }

    // MARK: - Where the file lives

    @Test
    func `a relative file sits in the dedicated working directory`() {
        let url = CLISessionRunner.fileURL(
            "probe-session.json",
            workingDirectory: .dedicated,
            homeDirectory: home,
            environment: { _ in nil }
        )

        #expect(url == CLIWorkingDirectory.resolve().appendingPathComponent("probe-session.json"))
    }

    @Test
    func `a relative file without a dedicated directory sits in home`() {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fake-home")
        let url = CLISessionRunner.fileURL(
            "probe-session.json",
            workingDirectory: nil,
            homeDirectory: home,
            environment: { _ in nil }
        )

        #expect(url == home.appendingPathComponent("probe-session.json"))
    }

    @Test
    func `an absolute or expanded file wins over any directory`() {
        let url = CLISessionRunner.fileURL(
            "/tmp/probe-session.json",
            workingDirectory: .dedicated,
            homeDirectory: home,
            environment: { _ in nil }
        )
        let tilde = CLISessionRunner.fileURL(
            "~/probe-session.json",
            workingDirectory: nil,
            homeDirectory: home,
            environment: { _ in nil }
        )

        #expect(url.path == "/tmp/probe-session.json")
        #expect(tilde == home.appendingPathComponent("probe-session.json"))
    }

    // MARK: - The fetcher wiring

    @Test
    func `a fetcher with a session block creates once then resumes`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        screen(usageScreen, executor: executor, launches: launches)
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clisession-\(UUID().uuidString)/probe-session.json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fetcher = CLIFetcher(
            call: call(session: SessionReuse(
                file: fileURL.path,
                create: ["--session-id", "{{id}}", "--name", "ClaudeBar Probe"],
                resume: ["--resume", "{{id}}"],
                recreateOn: [],
                unsupportedOn: []
            )),
            makeExecutor: { _ in executor }
        )

        _ = try await fetcher.fetch(with: nil)
        _ = try await fetcher.fetch(with: nil)

        #expect(launches.recorded.count == 2)
        #expect(launches.recorded[0].contains("--session-id"))
        #expect(launches.recorded[1].contains("--resume"))
    }

    @Test
    func `a fetcher without a session block runs its plain args`() async throws {
        let launches = Launches()
        let executor = MockCLIExecutor()
        screen(usageScreen, executor: executor, launches: launches)
        let fetcher = CLIFetcher(
            call: CLICall(cli: "claude", args: ["/usage", "--allowed-tools", ""], timeout: 20),
            makeExecutor: { _ in executor }
        )

        let response = try await fetcher.fetch(with: nil)

        #expect(launches.recorded.count == 1)
        #expect(launches.recorded[0] == ["/usage", "--allowed-tools", ""])
        #expect(response.text.contains("65% left"))
    }
}
