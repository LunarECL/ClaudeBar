import DataSources
import Quotas
import Foundation

/// A provider as data — what ships in `Resources/Providers/<id>.json` for a
/// built-in, and what *Add Provider* will write for a custom one. Validated
/// when parsed, so a `Provider` is only ever made from a definition that
/// keeps the laws below.
public struct ProviderDefinition: Sendable, Equatable, Codable {
    public struct Links: Sendable, Equatable, Codable {
        public let dashboard: URL?
        public let status: URL?
        /// A different dashboard for some plans — `{ "claudeApi": "…" }`. Keyed
        /// by the plan names mapping scripts use (`claudeMax`, `claudePro`,
        /// `claudeApi`) or a badge as written.
        public let dashboardByPlan: [String: URL]

        public init(dashboard: URL? = nil, status: URL? = nil, dashboardByPlan: [String: URL] = [:]) {
            self.dashboard = dashboard
            self.status = status
            self.dashboardByPlan = dashboardByPlan
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                dashboard: try container.decodeIfPresent(URL.self, forKey: .dashboard),
                status: try container.decodeIfPresent(URL.self, forKey: .status),
                dashboardByPlan: try container.decodeIfPresent([String: URL].self, forKey: .dashboardByPlan) ?? [:]
            )
        }

        /// The dashboard for the plan the last usage reported, else the default.
        public func dashboard(for plan: AccountTier?) -> URL? {
            guard let plan, let url = dashboardByPlan[Self.key(for: plan)] else { return dashboard }
            return url
        }

        static func key(for plan: AccountTier) -> String {
            switch plan {
            case .claudeMax: "claudeMax"
            case .claudePro: "claudePro"
            case .claudeApi: "claudeApi"
            case .custom(let badge): badge
            }
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
    /// More than one login for this provider: what an added account runs.
    public let accounts: Accounts?

    /// Accounts the person adds beside the default login (Codex, #326).
    /// Their data sources may name the account's saved values as
    /// `{{account.<name>}}` — filled in when the account's provider is made.
    public struct Accounts: Sendable, Equatable, Codable {
        /// The account's email is the provider's name — two logins of one
        /// product are told apart by who they are.
        public let nameFromEmail: Bool
        /// How a person adds one: by choosing the folder its login lives in.
        public let folder: Folder?
        /// What an added account runs in place of `dataSources`, with the
        /// same kinds, so one Data source choice covers every account.
        public let dataSources: [DataSourceDefinition]

        /// `{ "savedAs": "codexHome", "default": "${CODEX_HOME:-~/.codex}",
        /// "accountId": { "fact": "account", "savedAs": "chatgptAccountId" } }`
        /// — the folder and the login's account id are saved as the account's
        /// values; `notSignedIn` is what a folder without a login says.
        public struct Folder: Sendable, Equatable, Codable {
            public struct AccountId: Sendable, Equatable, Codable {
                /// The credential value that names the login.
                public let fact: String
                public let savedAs: String

                public init(fact: String, savedAs: String) {
                    self.fact = fact
                    self.savedAs = savedAs
                }
            }

            public let savedAs: String
            /// The default login's folder — never added a second time.
            public let `default`: String?
            public let accountId: AccountId
            public let notSignedIn: String?

            public init(savedAs: String, default folder: String? = nil, accountId: AccountId, notSignedIn: String? = nil) {
                self.savedAs = savedAs
                self.default = folder
                self.accountId = accountId
                self.notSignedIn = notSignedIn
            }
        }

        public init(nameFromEmail: Bool = false, folder: Folder? = nil, dataSources: [DataSourceDefinition] = []) {
            self.nameFromEmail = nameFromEmail
            self.folder = folder
            self.dataSources = dataSources
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nameFromEmail = try container.decodeIfPresent(Bool.self, forKey: .nameFromEmail) ?? false
            folder = try container.decodeIfPresent(Folder.self, forKey: .folder)
            dataSources = try container.decodeIfPresent([DataSourceDefinition].self, forKey: .dataSources) ?? []
        }
    }

    public init(
        id: String,
        name: String,
        cli: String? = nil,
        links: Links = Links(),
        enabledByDefault: Bool = true,
        dataSources: [DataSourceDefinition],
        defaultDataSource: String,
        accounts: Accounts? = nil
    ) {
        self.id = id
        self.name = name
        self.cli = cli
        self.links = links
        self.enabledByDefault = enabledByDefault
        self.dataSources = dataSources
        self.defaultDataSource = defaultDataSource
        self.accounts = accounts
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
        accounts = try container.decodeIfPresent(Accounts.self, forKey: .accounts)
    }

    /// Decodes and checks the laws: at least one data source, kinds unique,
    /// the default and every fallback naming one of them.
    public static func parse(_ data: Data) throws -> ProviderDefinition {
        let definition = try JSONDecoder().decode(ProviderDefinition.self, from: data)
        try definition.validate()
        return definition
    }

    /// The definition as an added account runs it: its `accounts.dataSources`
    /// in place of the default ones, with `{{account.<name>}}` filled from the
    /// account's saved values (JSON-escaped). `nil` for a definition without accounts.
    public static func parse(_ data: Data, account values: [String: String]) throws -> ProviderDefinition? {
        var text = String(decoding: data, as: UTF8.self)
        for (name, value) in values {
            let encoded = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
            text = text.replacingOccurrences(of: "{{account.\(name)}}", with: String(encoded.dropFirst().dropLast()))
        }
        let base = try parse(Data(text.utf8))
        guard let accounts = base.accounts, !accounts.dataSources.isEmpty else { return nil }
        let definition = ProviderDefinition(
            id: base.id, name: base.name, cli: base.cli, links: base.links,
            enabledByDefault: base.enabledByDefault, dataSources: accounts.dataSources,
            defaultDataSource: base.defaultDataSource, accounts: accounts
        )
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
        let handOffs = dataSources.flatMap { [$0.fallback?.to].compactMap { $0 } + Array($0.fallbackOn.values) }
        for kind in handOffs where !kinds.contains(kind) {
            throw DefinitionError.unknownDataSource(id, kind)
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
