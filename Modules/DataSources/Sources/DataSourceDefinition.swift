import Foundation

/// One data source as data — the JSON a provider definition lists under
/// `dataSources`. No behaviour: `DataSources.make` turns it into a
/// `DataSource` that fetches.
public struct DataSourceDefinition: Sendable, Equatable, Codable {
    /// What the person picks — `rpc`, `api`, `cli` … and the value of the
    /// provider's saved `<id>.probeMode`.
    public let kind: String
    public let label: String?
    public let summary: String?
    /// A data source only ever reached as another one's fallback.
    public let hidden: Bool
    public let credential: CredentialLookup?
    public let fetch: Fetch
    public let mapping: Mapping
    /// The data source to try when this one fails, optionally only while a
    /// provider setting allows it.
    public let fallback: Fallback?
    /// Hand-offs by failure: `{ "subscriptionRequired": "cliCost" }` tries
    /// that data source when this one fails that way, before `fallback`.
    public let fallbackOn: [String: String]
    /// Serve the last usage for this long instead of fetching again; a rate
    /// limit is remembered until it passes. Also the provider's background
    /// refresh floor while this data source is active.
    public let cache: Cache?
    /// JSON files the mapping may read — `{ "account": { "path": …, "email": "$.…" } }`.
    public let context: [String: JSONFileCredential]
    /// What to do once when the mapping reports a failure, then try again.
    public let recover: [String: Recovery]

    public init(
        kind: String,
        label: String? = nil,
        summary: String? = nil,
        hidden: Bool = false,
        credential: CredentialLookup? = nil,
        fetch: Fetch,
        mapping: Mapping,
        fallback: Fallback? = nil,
        fallbackOn: [String: String] = [:],
        cache: Cache? = nil,
        context: [String: JSONFileCredential] = [:],
        recover: [String: Recovery] = [:]
    ) {
        self.kind = kind
        self.label = label
        self.summary = summary
        self.hidden = hidden
        self.credential = credential
        self.fetch = fetch
        self.mapping = mapping
        self.fallback = fallback
        self.fallbackOn = fallbackOn
        self.cache = cache
        self.context = context
        self.recover = recover
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        credential = try container.decodeIfPresent(CredentialLookup.self, forKey: .credential)
        fetch = try container.decode(Fetch.self, forKey: .fetch)
        mapping = try container.decode(Mapping.self, forKey: .mapping)
        fallback = try container.decodeIfPresent(Fallback.self, forKey: .fallback)
        fallbackOn = try container.decodeIfPresent([String: String].self, forKey: .fallbackOn) ?? [:]
        cache = try container.decodeIfPresent(Cache.self, forKey: .cache)
        context = try container.decodeIfPresent([String: JSONFileCredential].self, forKey: .context) ?? [:]
        recover = try container.decodeIfPresent([String: Recovery].self, forKey: .recover) ?? [:]
    }
}

/// `"fallback": "tty"`, or `{ "to": "cli", "enabledBySetting": "cliFallbackEnabled" }`
/// — the setting is read as `<provider>.<name>`, and the fallback is on unless it says no.
public struct Fallback: Sendable, Equatable, Codable {
    public let to: String
    public let enabledBySetting: String?

    public init(to: String, enabledBySetting: String? = nil) {
        self.to = to
        self.enabledBySetting = enabledBySetting
    }

    public init(from decoder: Decoder) throws {
        if let to = try? decoder.singleValueContainer().decode(String.self) {
            self.init(to: to)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            to: try container.decode(String.self, forKey: .to),
            enabledBySetting: try container.decodeIfPresent(String.self, forKey: .enabledBySetting)
        )
    }
}

public struct Cache: Sendable, Equatable, Codable {
    /// Seconds.
    public let ttl: TimeInterval

    public init(ttl: TimeInterval) {
        self.ttl = ttl
    }
}

/// A fix tried once when the mapping reports a failure.
public enum Recovery: Sendable, Equatable, Codable {
    /// Sets one value deep inside a JSON file that already exists — e.g. a
    /// CLI's "trusted folder" flag. `keys` may hold `{{probeDirectory}}`.
    case patchJSONFile(path: String, keys: [String], value: JSONValue)

    private enum Keys: String, CodingKey { case patchJSONFile }
    private enum PatchKeys: String, CodingKey { case path, keys, value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let patch = try container.nestedContainer(keyedBy: PatchKeys.self, forKey: .patchJSONFile)
        self = .patchJSONFile(
            path: try patch.decode(String.self, forKey: .path),
            keys: try patch.decode([String].self, forKey: .keys),
            value: try patch.decode(JSONValue.self, forKey: .value)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .patchJSONFile(let path, let keys, let value):
            var patch = container.nestedContainer(keyedBy: PatchKeys.self, forKey: .patchJSONFile)
            try patch.encode(path, forKey: .path)
            try patch.encode(keys, forKey: .keys)
            try patch.encode(value, forKey: .value)
        }
    }
}
