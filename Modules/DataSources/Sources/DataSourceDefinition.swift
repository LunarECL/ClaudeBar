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
    /// The data source to try once when this one fails.
    public let fallback: String?

    public init(
        kind: String,
        label: String? = nil,
        summary: String? = nil,
        hidden: Bool = false,
        credential: CredentialLookup? = nil,
        fetch: Fetch,
        mapping: Mapping,
        fallback: String? = nil
    ) {
        self.kind = kind
        self.label = label
        self.summary = summary
        self.hidden = hidden
        self.credential = credential
        self.fetch = fetch
        self.mapping = mapping
        self.fallback = fallback
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
        fallback = try container.decodeIfPresent(String.self, forKey: .fallback)
    }
}
