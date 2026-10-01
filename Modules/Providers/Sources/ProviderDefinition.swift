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
    /// Logins added beside the default one, and how they differ.
    public let accounts: Accounts?

    /// Logins a person adds beside the default one (Codex, #326). An added
    /// login runs the SAME data sources with `patch` merged in (RFC 7396) and
    /// its saved values filling `{{account.<name>}}` — one definition, never
    /// a copy per login.
    public struct Accounts: Sendable, Equatable, Codable {
        /// The login's email names it — two logins of one product are told
        /// apart by who they are.
        public let nameFromEmail: Bool
        /// How a person adds one: by choosing the folder its login lives in.
        public let folder: Folder?
        /// By data source kind, what an added login changes — its own folder,
        /// its identity check, no fallback to the shared terminal. `null`
        /// leaves that data source out for added logins.
        public let patch: [String: JSONValue]

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

        public init(nameFromEmail: Bool = false, folder: Folder? = nil, patch: [String: JSONValue] = [:]) {
            self.nameFromEmail = nameFromEmail
            self.folder = folder
            self.patch = patch
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nameFromEmail = try container.decodeIfPresent(Bool.self, forKey: .nameFromEmail) ?? false
            folder = try container.decodeIfPresent(Folder.self, forKey: .folder)
            patch = try container.decodeIfPresent([String: JSONValue].self, forKey: .patch) ?? [:]
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

    /// The data sources an added login runs: each one with `accounts.patch`
    /// merged in and `{{account.<name>}}` filled from the login's `values`.
    /// Throws when a value the definition needs is missing.
    public func dataSources(forAccount values: [String: String]) throws -> [DataSourceDefinition] {
        let patch = accounts?.patch ?? [:]
        return try dataSources.compactMap { source -> DataSourceDefinition? in
            var adapted = source
            if let change = patch[source.kind] {
                if case .null = change { return nil }
                adapted = try source.patched(with: change)
            }
            adapted = try adapted.filled(values, scope: "account")
            if let missing = adapted.unfilled(scope: "account").first {
                throw DefinitionError.missingAccountValue(id, missing)
            }
            return adapted
        }
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
    case missingAccountValue(String, String)

    public var errorDescription: String? {
        switch self {
        case .noDataSources(let id): "Provider '\(id)' has no data sources"
        case .duplicateKind(let id, let kind): "Provider '\(id)' lists data source '\(kind)' twice"
        case .unknownDataSource(let id, let kind): "Provider '\(id)' names data source '\(kind)', which it doesn't have"
        case .missingFile(let name): "No provider definition named '\(name)'"
        case .missingAccountValue(let id, let name): "A '\(id)' account has no saved '\(name)'"
        }
    }
}
