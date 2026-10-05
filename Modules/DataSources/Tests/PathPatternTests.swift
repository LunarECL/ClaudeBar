import Foundation
import Quotas
import Testing
@testable import DataSources

/// *Which file on disk* has one owner (ENGINE_DESIGN §2.9): a `*` stands for
/// part of one folder name, a path may be a list, and of every match the
/// most recently changed file is the one read.
@Suite
struct PathPatternTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// A file under `home`, last changed `ago` seconds before now.
    @discardableResult
    private func write(_ relative: String, _ text: String = "{}", ago: TimeInterval = 0) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-ago)], ofItemAtPath: url.path)
        return url
    }

    private func resolve(_ pattern: PathPattern) -> String {
        Paths.resolve(pattern, homeDirectory: home, environment: { _ in nil })
    }

    @Test
    func `should read the most recently changed file a star matches`() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("JetBrains/PyCharm2025.2/options/quota.xml", ago: 3600)
        let newest = try write("JetBrains/IntelliJIdea2025.3/options/quota.xml", ago: 60)
        try write("JetBrains/WebStorm2024.1/options/quota.xml", ago: 86400)

        #expect(resolve("~/JetBrains/*/options/quota.xml") == newest.path)
    }

    @Test
    func `should read the newest match across every place a list names`() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("JetBrains/IntelliJIdea2025.3/options/quota.xml", ago: 3600)
        let newest = try write("Google/AndroidStudio2025.1/options/quota.xml", ago: 10)

        #expect(resolve(["~/JetBrains/*/options/quota.xml", "~/Google/*/options/quota.xml"]) == newest.path)
    }

    @Test
    func `should match a star within one folder name only`() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("JetBrains/IntelliJIdea2025.3/nested/options/quota.xml")

        #expect(!FileManager.default.fileExists(atPath: resolve("~/JetBrains/*/options/quota.xml")))
    }

    @Test
    func `should match part of a folder name`() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let idea = try write("JetBrains/IntelliJIdea2025.3/options/quota.xml", ago: 3600)
        try write("JetBrains/PyCharm2025.2/options/quota.xml", ago: 10)

        #expect(resolve("~/JetBrains/IntelliJ*/options/quota.xml") == idea.path)
    }

    @Test
    func `should mean what it always meant when a path has no star`() {
        #expect(resolve("~/.grok/auth.json") == home.appendingPathComponent(".grok/auth.json").path)
        #expect(resolve("/etc/hosts") == "/etc/hosts")
    }

    @Test
    func `should take the newest of a list of plain paths that exist`() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("a/auth.json", ago: 3600)
        let b = try write("b/auth.json", ago: 10)

        #expect(resolve(["~/a/auth.json", "~/b/auth.json", "~/c/auth.json"]) == b.path)
    }

    @Test
    func `should decode a path as one string or a list, and write it back the same way`() throws {
        let one = try JSONDecoder().decode(FileCall.self, from: Data(#"{"path":"~/a.json"}"#.utf8))
        let many = try JSONDecoder().decode(FileCall.self, from: Data(#"{"path":["~/a/*.json","~/b.json"]}"#.utf8))
        #expect(one.path == ["~/a.json"])
        #expect(many.path == ["~/a/*.json", "~/b.json"])
        #expect(String(decoding: try JSONEncoder().encode(one), as: UTF8.self) == #"{"path":"~\/a.json"}"#)
        #expect(try JSONDecoder().decode(FileCall.self, from: try JSONEncoder().encode(many)) == many)
    }

    @Test
    func `should read the newest matching file and not be ready when nothing matches`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("IDE/A1/quota.xml", "old", ago: 3600)
        try write("IDE/B2/quota.xml", "new", ago: 10)

        let found = FileFetcher(call: FileCall(path: "~/IDE/*/quota.xml"), homeDirectory: home, environment: { _ in nil })
        #expect(found.isReady())
        #expect(try await found.fetch(with: nil).text == "new")

        let missing = FileFetcher(call: FileCall(path: "~/IDE/*/other.xml"), homeDirectory: home, environment: { _ in nil })
        #expect(!missing.isReady())
    }

    @Test
    func `should find a key in the newest login file a star matches`() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("profiles/old/auth.json", #"{"token":"old"}"#, ago: 3600)
        try write("profiles/new/auth.json", #"{"token":"new"}"#, ago: 10)

        let lookup = try JSONDecoder().decode(CredentialLookup.self,
                                              from: Data(#"{"jsonFile":{"path":"~/profiles/*/auth.json","token":"$.token"}}"#.utf8))
        let reader = JSONFileReader(file: try #require(lookup.jsonFileCredential), homeDirectory: home, environment: { _ in nil })
        #expect(try reader.find()?.credential.token == "new")
    }

    @Test
    func `should list each place a key may be in the lookup order`() throws {
        let lookup = try JSONDecoder().decode(CredentialLookup.self,
                                              from: Data(#"{"jsonFile":{"path":["~/a/*/auth.json","~/b.json"],"token":"$.token"}}"#.utf8))
        #expect(lookup.lookupOrder == ["~/a/*/auth.json", "~/b.json"])
    }
}

private extension CredentialLookup {
    var jsonFileCredential: JSONFileCredential? {
        if case .jsonFile(let file) = self { return file }
        return nil
    }
}
