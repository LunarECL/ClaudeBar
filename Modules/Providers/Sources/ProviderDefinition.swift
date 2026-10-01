import DataSources
import Foundation

/// A provider as data — what ships in `Resources/Providers/<id>.json` for a
/// built-in, and what *Add Provider* will write for a custom one. Validated
/// when parsed, so a `Provider` is only ever made from a definition that
/// keeps the laws below.
public struct ProviderDefinition: Sendable, Equatable, Codable {
    public struct Links: Sendable, Equatable, Codable {
        public let dashboard: URL?
        public let status: URL?

        public init(dashboard: URL? = nil, status: URL? = nil) {
            self.dashboard = dashboard
            self.status = status
        }
    }

    /// Stable forever: settings, the menu-bar choice and the lineup are keyed by it.
    public let id: String
    public let name: String
    /// The CLI a person would run (`codex`), when there is one.
    public let cli: String?
    public let links: Links
    public let enabledByDefault: Bool
    public let dataSources: [DataSourceDefinition]
    public let defaultDataSource: String

    public init(
        id: String,
        name: String,
        cli: String? = nil,
        links: Links = Links(),
        enabledByDefault: Bool = true,
        dataSources: [DataSourceDefinition],
        defaultDataSource: String
    ) {
        self.id = id
        self.name = name
        self.cli = cli
        self.links = links
        self.enabledByDefault = enabledByDefault
        self.dataSources = dataSources
        self.defaultDataSource = defaultDataSource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cli = try container.decodeIfPresent(String.self, forKey: .cli)
        links = try container.decodeIfPresent(Links.self, forKey: .links) ?? Links()
        enabledByDefault = try container.decodeIfPresent(Bool.self, forKey: .enabledByDefault) ?? true
        dataSources = try container.decode([DataSourceDefinition].self, forKey: .dataSources)
        defaultDataSource = try container.decode(String.self, forKey: .defaultDataSource)
    }

    /// Decodes and checks the laws: at least one data source, kinds unique,
    /// the default and every fallback naming one of them.
    public static func parse(_ data: Data) throws -> ProviderDefinition {
        let definition = try JSONDecoder().decode(ProviderDefinition.self, from: data)
        try definition.validate()
        return definition
    }

    public func validate() throws {
        guard !dataSources.isEmpty else { throw DefinitionError.noDataSources(id) }
        var kinds = Set<String>()
        for source in dataSources {
            guard kinds.insert(source.kind).inserted else {
                throw DefinitionError.duplicateKind(id, source.kind)
            }
        }
        guard kinds.contains(defaultDataSource) else {
            throw DefinitionError.unknownDataSource(id, defaultDataSource)
        }
        for case let fallback? in dataSources.map(\.fallback) where !kinds.contains(fallback) {
            throw DefinitionError.unknownDataSource(id, fallback)
        }
    }

    public func dataSource(_ kind: String) -> DataSourceDefinition? {
        dataSources.first { $0.kind == kind }
    }
}

public enum DefinitionError: Error, Sendable, Equatable, LocalizedError {
    case noDataSources(String)
    case duplicateKind(String, String)
    case unknownDataSource(String, String)
    case missingFile(String)

    public var errorDescription: String? {
        switch self {
        case .noDataSources(let id): "Provider '\(id)' has no data sources"
        case .duplicateKind(let id, let kind): "Provider '\(id)' lists data source '\(kind)' twice"
        case .unknownDataSource(let id, let kind): "Provider '\(id)' names data source '\(kind)', which it doesn't have"
        case .missingFile(let name): "No provider definition named '\(name)'"
        }
    }
}
