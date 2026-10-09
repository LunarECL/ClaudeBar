import Foundation

/// A place on disk a definition names: one path, or a list of them. A `*`
/// stands for part of one folder or file name. `"path": "~/a.json"` and
/// `"path": ["~/JetBrains/*/x.xml", "~/Google/*/x.xml"]` both decode; it is
/// written back the way it was given. `Paths.resolve` says which file it is.
public struct PathPattern: Sendable, Equatable, Codable, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
                           CustomStringConvertible {
    /// Every place, in the order given. Never empty.
    public let places: [String]

    public init(_ path: String) {
        places = [path]
    }

    public init(_ paths: [String]) {
        places = paths.isEmpty ? [""] : paths
    }

    public init(stringLiteral path: String) {
        self.init(path)
    }

    public init(arrayLiteral paths: String...) {
        self.init(paths)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let path = try? container.decode(String.self) {
            self.init(path)
        } else {
            let paths = try container.decode([String].self)
            guard !paths.isEmpty else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "A path list needs at least one path")
            }
            self.init(paths)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if places.count == 1 { try container.encode(places[0]) } else { try container.encode(places) }
    }

    /// As a person reads it in Settings: the places, in order.
    public var description: String { places.joined(separator: " · ") }

    /// The pattern with each place changed — a template filled, say.
    public func map(_ transform: (String) -> String) -> PathPattern {
        PathPattern(places.map(transform))
    }
}

/// Which file on disk a definition means — the one owner of that rule
/// (ENGINE_DESIGN §2.9). `~/…` and `${VARIABLE:-default}/…` expand; a `*`
/// matches within one name; of every file that matches, in every place, the
/// most recently changed is the one. When none matches, the first place as
/// written, which is missing.
enum Paths {
    static func resolve(_ pattern: PathPattern, homeDirectory: URL, environment: @Sendable (String) -> String?) -> String {
        let expanded = pattern.places.map { expand($0, homeDirectory: homeDirectory, environment: environment) }
        if expanded.count == 1, !expanded[0].contains("*") { return expanded[0] }
        let matches = expanded.flatMap(Self.matches)
        let newest = matches.max { changed($0) < changed($1) }
        return newest ?? expanded[0]
    }

    /// `~/…` and `${VARIABLE:-default}/…` in one path.
    static func expand(_ path: String, homeDirectory: URL, environment: @Sendable (String) -> String?) -> String {
        var path = path
        if path.hasPrefix("${"), let close = path.firstIndex(of: "}") {
            let inner = path[path.index(path.startIndex, offsetBy: 2)..<close]
            let parts = inner.components(separatedBy: ":-")
            let value = environment(parts[0]).flatMap { $0.isEmpty ? nil : $0 } ?? (parts.count > 1 ? parts[1] : "")
            path = value + path[path.index(after: close)...]
        }
        if path == "~" { return homeDirectory.path }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }

    /// The existing files and folders one expanded path names, a `*`
    /// matching within one name.
    private static func matches(_ path: String) -> [String] {
        guard path.contains("*") else {
            return FileManager.default.fileExists(atPath: path) ? [path] : []
        }
        var found = [path.hasPrefix("/") ? "/" : ""]
        for name in path.split(separator: "/").map(String.init) {
            found = found.flatMap { folder -> [String] in
                guard name.contains("*") else { return [folder + name + "/"] }
                let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.isEmpty ? "." : folder)) ?? []
                return entries.filter { Wildcard.matches(name, $0) }.sorted().map { folder + $0 + "/" }
            }
        }
        return found.map { String($0.dropLast()) }.filter { FileManager.default.fileExists(atPath: $0) }
    }

    private static func changed(_ path: String) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
    }
}
