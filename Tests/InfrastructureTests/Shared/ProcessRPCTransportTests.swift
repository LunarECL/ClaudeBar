import Testing
import Foundation
@testable import Infrastructure

@Suite
struct ProcessRPCTransportTests {

    /// CLIs that trust-check the directory they start in (Codex 0.150+, #267)
    /// must see the directory the caller picked, or they refuse to answer.
    /// `pwd` echoes back the cwd the child was given.
    @Test
    func `runs the child in the requested working directory`() async throws {
        // Live under the test runner's cwd so no symlink rewriting is in play:
        // both sides here are getcwd() output for the same directory.
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let requested = base.appendingPathComponent("ProcessRPCTransportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: requested) }

        let transport = try ProcessRPCTransport(executable: "/bin/pwd", arguments: [], workingDirectory: requested)
        defer { transport.close() }

        let data = try await transport.receive()
        let childCWD = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(childCWD == requested.path)
    }

    @Test
    func `inherits the caller working directory when none is requested`() async throws {
        let transport = try ProcessRPCTransport(executable: "/bin/pwd", arguments: [])
        defer { transport.close() }

        let data = try await transport.receive()
        let childCWD = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        // `pwd` may report the logical path ($PWD) while getcwd() here reports
        // the physical one; only the /private prefix can differ on macOS.
        #expect(normalized(childCWD) == normalized(FileManager.default.currentDirectoryPath))
    }

    private func normalized(_ path: String?) -> String {
        guard var path, path.hasPrefix("/private/") else { return path ?? "" }
        path.removeFirst("/private".count)
        return path
    }
}
