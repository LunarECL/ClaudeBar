#if os(Windows)
import Foundation
import Testing
@testable import DataSources

/// Windows finds a CLI as `where` does, and takes a path to one as it is.
@Suite
struct PathBinaryLocatorTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// An empty file at `name` under `root`, and its path.
    private func file(_ name: String) throws -> String {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        return url.path
    }

    private func locator(path: [String], pathext: String = ".COM;.EXE;.BAT;.CMD") -> PathBinaryLocator {
        let variables = ["Path": path.joined(separator: ";"), "PATHEXT": pathext]
        return PathBinaryLocator(environment: { variables })
    }

    @Test
    func `should find a name in the first PATH folder that has it, with an extension PATHEXT lists`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let npm = try file("npm/claude.cmd")
        _ = try file("later/claude.exe")
        _ = try file("npm/claude.ps1")

        let path = [root.appendingPathComponent("empty").path, root.appendingPathComponent("npm").path,
                    root.appendingPathComponent("later").path]
        #expect(locator(path: path).locate("claude") == npm)
    }

    @Test
    func `should take a full path to the CLI as it is, without searching PATH`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = try file("tools/claude.exe")
        _ = try file("bin/claude.exe")

        let locator = locator(path: [root.appendingPathComponent("bin").path])
        #expect(locator.locate(tools) == tools)
        #expect(locator.locate(root.appendingPathComponent("tools/claude").path) == tools)
        #expect(locator.locate(root.appendingPathComponent("gone/claude.exe").path) == nil)
    }

    @Test
    func `should not find a CLI that no PATH folder holds`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try file("bin/claude.exe")

        #expect(locator(path: [root.appendingPathComponent("bin").path]).locate("codex") == nil)
    }
}
#endif
