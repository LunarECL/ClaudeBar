import Foundation
import Testing
@testable import Providers

/// A setting's kind owns its rule; a choice's options carry their values.
@Suite
struct SettingTests {
    private func decode(_ json: String) throws -> Setting {
        try JSONDecoder().decode(Setting.self, from: Data(json.utf8))
    }

    private let region = """
    {"id":"region","label":"Region","scope":"account","default":"china",
     "kind":{"choice":[{"id":"china","label":"China","site":"acme.cn"},{"id":"international","label":"International","site":"acme.com"}]}}
    """

    @Test
    func `should fill in the chosen option and every value it carries`() throws {
        let setting = try decode(region)
        #expect(setting.fills(for: "international") == ["region": "international", "region.site": "acme.com"])
    }

    @Test
    func `should use the default for a blank, or the first option when a choice has no default`() throws {
        #expect(try decode(region).value(from: "  ") == "china")
        let noDefault = try decode(#"{"id":"plan","label":"Plan","kind":{"choice":["pro","max"]}}"#)
        #expect(noDefault.value(from: nil) == "pro")
        #expect(noDefault.value(from: " max ") == "max")
    }

    @Test
    func `should never fill a key into a request except by looking it up`() throws {
        let key = try decode(#"{"id":"apiKey","label":"API key","kind":"secret"}"#)
        #expect(key.fills(for: "sk-1").isEmpty)
    }

    @Test
    func `should refuse a key that comes with a default`() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"id":"apiKey","label":"API key","kind":"secret","default":"sk-0"}"#)
        }
    }

    @Test
    func `should still read settings written in the older form`() throws {
        #expect(try decode(#"{"id":"apiKey","label":"API key","secret":true}"#).kind == .secret)
        #expect(try decode(#"{"id":"region","label":"Region","choices":["a","b"]}"#).kind
            == .choice([Setting.Option(id: "a"), Setting.Option(id: "b")]))
    }

    @Test
    func `should say what is wrong with a choice, text or folder the person entered`() throws {
        let paths = FakePaths(folders: ["/Users/me/.acme-work"])
        #expect(try decode(region).check("mars", paths: paths) == "Choose a Region from the list.")
        #expect(try decode(region).check("china", paths: paths) == nil)
        let profile = try decode(#"{"id":"profile","label":"Profile","kind":{"text":{"pattern":"^[a-z]+$"}}}"#)
        #expect(profile.check("Work 1", paths: paths) == "Enter a valid Profile.")
        let folder = try decode(#"{"id":"home","label":"CLI data folder","kind":{"path":{"mustExist":true}}}"#)
        #expect(folder.check("relative/dir", paths: paths) == "Enter a full path for CLI data folder.")
        #expect(folder.check("/Users/me/missing", paths: paths) == "Choose an existing folder for CLI data folder.")
        #expect(folder.check("/Users/me/.acme-work", paths: paths) == nil)
        #expect(folder.check("", paths: paths) == "Fill in CLI data folder.")
    }

    @Test
    func `should find a login's folder among its values, and no folder for a choice`() throws {
        let folder = try decode(#"{"id":"home","label":"Folder","scope":"account","kind":"path"}"#)
        #expect(folder.path(in: ["home": "/Users/me/work"]) == "/Users/me/work")
        #expect(try decode(region).path(in: ["region": "china"]) == nil)
    }

    @Test
    func `should treat two spellings of one folder as the same place, but never two equal choices`() throws {
        let paths = FakePaths(folders: [], aliases: ["~/.acme": "/Users/me/.acme"])
        let folder = try decode(#"{"id":"home","label":"Folder","kind":"path"}"#)
        #expect(folder.isSamePlace("~/.acme", as: "/Users/me/.acme", paths: paths))
        #expect(try decode(region).isSamePlace("china", as: "china", paths: paths) == false)
    }

    @Test
    func `should keep a setting as written when it is saved and read back`() throws {
        let setting = try decode(region)
        #expect(try JSONDecoder().decode(Setting.self, from: JSONEncoder().encode(setting)) == setting)
    }
}

/// The file system as a test needs it: these folders exist, and these
/// spellings are the same place.
struct FakePaths: PathChecking {
    var folders: Set<String>
    var aliases: [String: String] = [:]

    func isFolder(_ path: String) -> Bool { folders.contains(canonical(path)) }
    func canonical(_ path: String) -> String { aliases[path] ?? path }
}
