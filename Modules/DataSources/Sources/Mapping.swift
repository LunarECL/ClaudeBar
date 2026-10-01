import Domain
import Foundation

/// WHAT THE BYTES SAY — *Map fields*. A closed sum: a JSON response is read by
/// paths, a terminal screen by patterns.
public enum Mapping: Sendable, Equatable {
    case json(JSONMapping)
    case text(TextMapping)
    /// A format no rule can say — a TUI screen, a money shape — read by a
    /// JavaScript file run in JavaScriptCore, with no file, network or
    /// process access.
    case script(ScriptMapping)
}

/// `{ "script": { "file": "claude-usage-screen.js", "credential": ["subscriptionType"] } }`
///
/// The script defines `read(response, context)` and returns
/// `{ quotas, plan, cost, account }` or `{ error }`. It sees only the
/// credential values named here — never a token.
public struct ScriptMapping: Sendable, Equatable, Codable {
    public let file: String
    public let credential: [String]

    public init(file: String, credential: [String] = []) {
        self.file = file
        self.credential = credential
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decode(String.self, forKey: .file)
        credential = try container.decodeIfPresent([String].self, forKey: .credential) ?? []
    }
}

// MARK: - Shared vocabulary

/// Which kind of quota a rule produces — today's `QuotaType`.
public enum QuotaKind: String, Sendable, Equatable, Codable {
    /// The rolling 5-hour window ("Session").
    case session
    /// The rolling 7-day window ("Weekly").
    case weekly
    /// A model-specific limit, named by the rule.
    case model
    /// Any other named limit, named by the rule.
    case time
}

/// A value read from the response: a path, or a constant written in the
/// definition. A list of them means *the first that answers*.
///
/// Paths: `$.a.b` from the root · `a.b` from the current object · `$header.x`
/// for a response header · `$key` for the current key while repeating over a map.
public enum ValueRef: Sendable, Equatable, Codable {
    case path(String)
    case constant(Double)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .constant(number)
        } else {
            self = .path(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .path(let path): try container.encode(path)
        case .constant(let number): try container.encode(number)
        }
    }
}

/// When a quota resets, from one of the shapes providers use.
public enum ResetRef: Sendable, Equatable, Codable {
    case epochSeconds(String)
    case secondsFromNow(String)
    case iso8601(String)

    private static let tags = ["epochSeconds", "secondsFromNow", "iso8601"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        let tag = try container.singleTag(of: Self.tags, in: "resetsAt")
        let path = try container.decode(String.self, forKey: TagKey(tag))
        switch tag {
        case "epochSeconds": self = .epochSeconds(path)
        case "secondsFromNow": self = .secondsFromNow(path)
        default: self = .iso8601(path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .epochSeconds(let path): try container.encode(path, forKey: TagKey("epochSeconds"))
        case .secondsFromNow(let path): try container.encode(path, forKey: TagKey("secondsFromNow"))
        case .iso8601(let path): try container.encode(path, forKey: TagKey("iso8601"))
        }
    }
}

/// A window's length, in the unit the provider reports it in.
public enum DurationRef: Sendable, Equatable, Codable {
    case seconds(String)
    case minutes(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        let tag = try container.singleTag(of: ["seconds", "minutes"], in: "window")
        let path = try container.decode(String.self, forKey: TagKey(tag))
        self = tag == "seconds" ? .seconds(path) : .minutes(path)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .seconds(let path): try container.encode(path, forKey: TagKey("seconds"))
        case .minutes(let path): try container.encode(path, forKey: TagKey("minutes"))
        }
    }
}

/// A quota's name: fixed text, or read from the response and tidied.
public struct NameRule: Sendable, Equatable, Codable {
    /// Strips a prefix (case-insensitively); `capitalize` upper-cases the
    /// first letter of what is left.
    public struct Prefix: Sendable, Equatable, Codable {
        public let prefix: String
        public let capitalize: Bool

        public init(prefix: String, capitalize: Bool = false) {
            self.prefix = prefix
            self.capitalize = capitalize
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            prefix = try container.decode(String.self, forKey: .prefix)
            capitalize = try container.decodeIfPresent(Bool.self, forKey: .capitalize) ?? false
        }
    }

    public let text: String?
    public let firstOf: [String]
    /// The first prefix that matches is the one dropped.
    public let dropPrefixes: [Prefix]

    public init(text: String? = nil, firstOf: [String] = [], dropPrefixes: [Prefix] = []) {
        self.text = text
        self.firstOf = firstOf
        self.dropPrefixes = dropPrefixes
    }

    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(text: text)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: try container.decodeIfPresent(String.self, forKey: .text),
            firstOf: try container.decodeIfPresent([String].self, forKey: .firstOf) ?? [],
            dropPrefixes: try container.decodeIfPresent([Prefix].self, forKey: .dropPrefixes) ?? []
        )
    }
}

/// The failure a rule reports, as one of today's `ProbeError`s.
public enum ErrorRef: Sendable, Equatable, Codable {
    case authenticationRequired
    case updateRequired
    case folderTrustRequired
    case subscriptionRequired
    case noData
    case parseFailed(String)
    case sessionExpired(String?)
    case executionFailed(String)

    public var probeError: ProbeError {
        switch self {
        case .authenticationRequired: .authenticationRequired
        case .updateRequired: .updateRequired
        case .folderTrustRequired: .folderTrustRequired
        case .subscriptionRequired: .subscriptionRequired
        case .noData: .noData
        case .parseFailed(let reason): .parseFailed(reason)
        case .sessionExpired(let hint): .sessionExpired(hint: hint)
        case .executionFailed(let reason): .executionFailed(reason)
        }
    }

    public init(from decoder: Decoder) throws {
        if let tag = try? decoder.singleValueContainer().decode(String.self) {
            switch tag {
            case "authenticationRequired": self = .authenticationRequired
            case "updateRequired": self = .updateRequired
            case "folderTrustRequired": self = .folderTrustRequired
            case "subscriptionRequired": self = .subscriptionRequired
            case "noData": self = .noData
            case "sessionExpired": self = .sessionExpired(nil)
            default:
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown error '\(tag)'"))
            }
            return
        }
        let container = try decoder.container(keyedBy: TagKey.self)
        let tag = try container.singleTag(of: ["parseFailed", "sessionExpired", "executionFailed"], in: "error")
        let text = try container.decode(String.self, forKey: TagKey(tag))
        switch tag {
        case "parseFailed": self = .parseFailed(text)
        case "executionFailed": self = .executionFailed(text)
        default: self = .sessionExpired(text)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .parseFailed(let reason):
            var container = encoder.container(keyedBy: TagKey.self)
            try container.encode(reason, forKey: TagKey("parseFailed"))
        case .sessionExpired(let hint?):
            var container = encoder.container(keyedBy: TagKey.self)
            try container.encode(hint, forKey: TagKey("sessionExpired"))
        case .executionFailed(let reason):
            var container = encoder.container(keyedBy: TagKey.self)
            try container.encode(reason, forKey: TagKey("executionFailed"))
        default:
            var container = encoder.singleValueContainer()
            let tag: String = switch self {
            case .authenticationRequired: "authenticationRequired"
            case .updateRequired: "updateRequired"
            case .folderTrustRequired: "folderTrustRequired"
            case .subscriptionRequired: "subscriptionRequired"
            case .noData: "noData"
            default: "sessionExpired"
            }
            try container.encode(tag)
        }
    }
}

// MARK: - JSON mapping

/// Reads a JSON response by paths — *Used · Remaining · Limit · Resets*.
public struct JSONMapping: Sendable, Equatable, Codable {
    public let plan: PlanRule?
    public let quotas: [QuotaRule]
    public let cost: CostRule?
    /// What to do when no quota answered.
    public let whenEmpty: EmptyRule?

    public init(plan: PlanRule? = nil, quotas: [QuotaRule], cost: CostRule? = nil, whenEmpty: EmptyRule? = nil) {
        self.plan = plan
        self.quotas = quotas
        self.cost = cost
        self.whenEmpty = whenEmpty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decodeIfPresent(PlanRule.self, forKey: .plan)
        quotas = try container.decodeIfPresent([QuotaRule].self, forKey: .quotas) ?? []
        cost = try container.decodeIfPresent(CostRule.self, forKey: .cost)
        whenEmpty = try container.decodeIfPresent(EmptyRule.self, forKey: .whenEmpty)
    }
}

/// One quota — or, with `each`, one per element of an array or map.
public struct QuotaRule: Sendable, Equatable, Codable {
    /// A sub-object to read per element, and the suffix its quota's name gets
    /// ("Spark" · "Spark 7d").
    public struct WindowPick: Sendable, Equatable, Codable {
        public let at: String
        public let suffix: String

        public init(at: String, suffix: String = "") {
            self.at = at
            self.suffix = suffix
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            at = try container.decode(String.self, forKey: .at)
            suffix = try container.decodeIfPresent(String.self, forKey: .suffix) ?? ""
        }
    }

    public let kind: QuotaKind
    public let name: NameRule?
    /// The object the values are read from.
    public let at: String?
    /// Repeat over this array, or this map in key order.
    public let each: String?
    /// Map keys not to repeat over.
    public let skipKeys: [String]
    /// Per element, read these sub-objects instead of the element itself.
    public let windows: [WindowPick]
    public let usedPercent: [ValueRef]
    public let leftPercent: [ValueRef]
    public let resetsAt: [ResetRef]
    public let window: DurationRef?
    /// Fixed text in place of the reset countdown ("Free plan").
    public let resetText: String?

    enum CodingKeys: String, CodingKey {
        case kind, name, at, each, skipKeys, windows, usedPercent, leftPercent, resetsAt, window, resetText
    }

    public init(
        kind: QuotaKind,
        name: NameRule? = nil,
        at: String? = nil,
        each: String? = nil,
        skipKeys: [String] = [],
        windows: [WindowPick] = [],
        usedPercent: [ValueRef] = [],
        leftPercent: [ValueRef] = [],
        resetsAt: [ResetRef] = [],
        window: DurationRef? = nil,
        resetText: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.at = at
        self.each = each
        self.skipKeys = skipKeys
        self.windows = windows
        self.usedPercent = usedPercent
        self.leftPercent = leftPercent
        self.resetsAt = resetsAt
        self.window = window
        self.resetText = resetText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(QuotaKind.self, forKey: .kind)
        name = try container.decodeIfPresent(NameRule.self, forKey: .name)
        at = try container.decodeIfPresent(String.self, forKey: .at)
        each = try container.decodeIfPresent(String.self, forKey: .each)
        skipKeys = try container.decodeIfPresent([String].self, forKey: .skipKeys) ?? []
        windows = try container.decodeIfPresent([WindowPick].self, forKey: .windows) ?? []
        usedPercent = try Self.decodeList(ValueRef.self, container, .usedPercent)
        leftPercent = try Self.decodeList(ValueRef.self, container, .leftPercent)
        resetsAt = try Self.decodeList(ResetRef.self, container, .resetsAt)
        window = try container.decodeIfPresent(DurationRef.self, forKey: .window)
        resetText = try container.decodeIfPresent(String.self, forKey: .resetText)
    }

    /// One value or a list of them — `"used_percent"` or `["$header.x", "used_percent"]`.
    private static func decodeList<T: Decodable>(_ type: T.Type, _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [T] {
        if let list = try? container.decodeIfPresent([T].self, forKey: key) { return list }
        return try container.decodeIfPresent(T.self, forKey: key).map { [$0] } ?? []
    }
}

/// The plan badge — "PLUS", "PRO" — from a field, upper-cased unless `badges`
/// names it.
public struct PlanRule: Sendable, Equatable, Codable {
    public let path: String
    public let badges: [String: String]

    public init(path: String, badges: [String: String] = [:]) {
        self.path = path
        self.badges = badges
    }

    public init(from decoder: Decoder) throws {
        if let path = try? decoder.singleValueContainer().decode(String.self) {
            self.init(path: path)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode(String.self, forKey: .path),
            badges: try container.decodeIfPresent([String: String].self, forKey: .badges) ?? [:]
        )
    }
}

/// Money gone — "EXTRA USAGE" or "API COST" — from what is left of a limit,
/// or what was used.
public struct CostRule: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case apiCost
        case extraUsage
    }

    public let kind: Kind
    public let remaining: [ValueRef]
    public let used: [ValueRef]
    public let limit: [ValueRef]

    enum CodingKeys: String, CodingKey {
        case kind, remaining, used, limit
    }

    public init(kind: Kind = .apiCost, remaining: [ValueRef] = [], used: [ValueRef] = [], limit: [ValueRef] = []) {
        self.kind = kind
        self.remaining = remaining
        self.used = used
        self.limit = limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .apiCost
        remaining = try Self.list(container, .remaining)
        used = try Self.list(container, .used)
        limit = try Self.list(container, .limit)
    }

    private static func list(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [ValueRef] {
        if let list = try? container.decodeIfPresent([ValueRef].self, forKey: key) { return list }
        return try container.decodeIfPresent(ValueRef.self, forKey: key).map { [$0] } ?? []
    }
}

/// When nothing answered: fixed quotas if a field says so, otherwise a failure.
public struct EmptyRule: Sendable, Equatable, Codable {
    public struct Condition: Sendable, Equatable, Codable {
        public let path: String
        public let equals: String

        public init(path: String, equals: String) {
            self.path = path
            self.equals = equals
        }
    }

    public let condition: Condition?
    public let quotas: [QuotaRule]
    /// The `parseFailed` reason when the condition does not hold.
    public let otherwise: String?

    public init(condition: Condition? = nil, quotas: [QuotaRule] = [], otherwise: String? = nil) {
        self.condition = condition
        self.quotas = quotas
        self.otherwise = otherwise
    }

    enum CodingKeys: String, CodingKey {
        case condition = "if"
        case quotas
        case otherwise
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        condition = try container.decodeIfPresent(Condition.self, forKey: .condition)
        quotas = try container.decodeIfPresent([QuotaRule].self, forKey: .quotas) ?? []
        otherwise = try container.decodeIfPresent(String.self, forKey: .otherwise)
    }
}

// MARK: - Text mapping

/// Reads a terminal screen by patterns: errors first, then each quota's label
/// and the percentage within a few lines of it.
public struct TextMapping: Sendable, Equatable, Codable {
    public struct ErrorRule: Sendable, Equatable, Codable {
        /// Any of these phrases (case-insensitive)…
        public let contains: [String]
        /// …and all of these, when given.
        public let alsoContains: [String]
        public let error: ErrorRef

        public init(contains: [String], alsoContains: [String] = [], error: ErrorRef) {
            self.contains = contains
            self.alsoContains = alsoContains
            self.error = error
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            contains = try container.decode([String].self, forKey: .contains)
            alsoContains = try container.decodeIfPresent([String].self, forKey: .alsoContains) ?? []
            error = try container.decode(ErrorRef.self, forKey: .error)
        }
    }

    public struct QuotaPattern: Sendable, Equatable, Codable {
        public let kind: QuotaKind
        public let name: String?
        /// The line that names the quota (case-insensitive substring).
        public let label: String
        /// A regex whose first group is the percentage **left**.
        public let leftPercent: String?
        /// A regex whose first group is the percentage **used**.
        public let usedPercent: String?
        /// How many lines from the label to look.
        public let lookahead: Int

        public init(kind: QuotaKind, name: String? = nil, label: String, leftPercent: String? = nil, usedPercent: String? = nil, lookahead: Int = 12) {
            self.kind = kind
            self.name = name
            self.label = label
            self.leftPercent = leftPercent
            self.usedPercent = usedPercent
            self.lookahead = lookahead
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(QuotaKind.self, forKey: .kind)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            label = try container.decode(String.self, forKey: .label)
            leftPercent = try container.decodeIfPresent(String.self, forKey: .leftPercent)
            usedPercent = try container.decodeIfPresent(String.self, forKey: .usedPercent)
            lookahead = try container.decodeIfPresent(Int.self, forKey: .lookahead) ?? 12
        }
    }

    public let errors: [ErrorRule]
    public let quotas: [QuotaPattern]
    /// The `parseFailed` reason when no quota is found.
    public let whenEmpty: String?

    public init(errors: [ErrorRule] = [], quotas: [QuotaPattern], whenEmpty: String? = nil) {
        self.errors = errors
        self.quotas = quotas
        self.whenEmpty = whenEmpty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errors = try container.decodeIfPresent([ErrorRule].self, forKey: .errors) ?? []
        quotas = try container.decode([QuotaPattern].self, forKey: .quotas)
        whenEmpty = try container.decodeIfPresent(String.self, forKey: .whenEmpty)
    }
}

// MARK: - JSON

extension Mapping: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        switch try container.singleTag(of: ["json", "text", "script"], in: "mapping") {
        case "json": self = .json(try container.decode(JSONMapping.self, forKey: TagKey("json")))
        case "script": self = .script(try container.decode(ScriptMapping.self, forKey: TagKey("script")))
        default: self = .text(try container.decode(TextMapping.self, forKey: TagKey("text")))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .json(let mapping): try container.encode(mapping, forKey: TagKey("json"))
        case .text(let mapping): try container.encode(mapping, forKey: TagKey("text"))
        case .script(let mapping): try container.encode(mapping, forKey: TagKey("script"))
        }
    }
}
