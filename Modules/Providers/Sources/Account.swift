import DataSources
import Quotas
import Foundation
import Observation

/// A LOGIN YOU PAY FOR — who it is, its saved values, and what we last saw for
/// it. Two Codex logins are two accounts of one `Provider`: two things to
/// watch (each its own pill and menu-bar entry), one thing to fix.
///
/// An account has no fetching of its own. It conforms to `AIProvider` only as
/// a shim, forwarding to its provider, so the monitor, the pills and the menu
/// bar keep working until `AIProvider` folds into `Provider`.
@MainActor
@Observable
public final class Account: AIProvider {
    /// The product this login belongs to. Held strongly: the app keeps
    /// accounts, and an account needs its provider to fetch.
    public let provider: Provider
    /// `codex` for the default login, `codex.<account>` for an added one —
    /// the ids every saved setting and menu-bar pin is keyed by.
    public let id: String
    public let isDefault: Bool
    /// The login's own id within the provider — `default` for the default login.
    public let accountId: String
    /// The name the person gave it — empty when they gave none.
    public internal(set) var label: String
    /// What the person gave, or its login file holds.
    public let email: String?
    /// Its account settings — the Codex folder, the login's account id.
    public let values: [String: String]
    /// How it was added — `nil` for the default login and for logins saved
    /// before it was recorded.
    public let madeBy: AccountOrigin?

    /// The login's own *Pause* — never the product's switch.
    public var isEnabled: Bool {
        didSet {
            if isDefault {
                provider.settings.setOn(isEnabled, Provider.plainLoginKey, forProvider: provider.id)
            } else {
                provider.settings.setEnabled(isEnabled, forProvider: id)
            }
        }
    }

    /// In the lineup — pills, menu bar, refreshes, alerts: the login is on,
    /// and so is its product.
    public var isInLineup: Bool { isEnabled && provider.isEnabled }

    // MARK: - What we last saw

    public internal(set) var isSyncing = false
    public internal(set) var snapshot: UsageSnapshot?
    /// Today's `UsageError`, so every screen that reads one keeps reading one.
    public internal(set) var lastError: Error?
    /// Which step failed last — lookup, fetch or mapping. `nil` after a success.
    public internal(set) var lastFailedStep: DataSourceError.Step?
    /// The kind of the data source that produced `snapshot` — *via RPC*.
    public internal(set) var answeredBy: String?

    /// What Settings calls that data source — *RPC*, *API*, *Terminal*.
    public var answeredByLabel: String? {
        answeredBy.map { provider.definition.dataSource($0)?.label ?? $0 }
    }

    init(provider: Provider, login: ProviderAccount, values: [String: String], madeBy: AccountOrigin? = nil) {
        self.provider = provider
        self.id = login.id
        self.isDefault = login.isDefault
        self.accountId = login.accountId
        self.label = login.label
        self.email = login.email
        self.values = values
        self.madeBy = madeBy
        self.isEnabled = login.isDefault
            ? provider.settings.isOn(Provider.plainLoginKey, forProvider: provider.definition.id) ?? true
            : provider.settings.isEnabled(forProvider: login.id, defaultValue: provider.definition.enabledByDefault)
    }

    /// *NOT SET UP* — no usage yet, and the last refresh found no tool on
    /// this Mac or no sign-in to read with. Waiting for the person, not
    /// failing: the definition's `setup` says what it takes (#198).
    public var needsSetup: Bool {
        guard snapshot == nil, let error = lastError as? UsageError else { return false }
        switch error {
        case .cliNotFound, .authenticationRequired: return true
        default: return false
        }
    }

    /// What setting this login up takes: its definition's words, or its
    /// name and what failed when the definition says nothing.
    public var setupNotice: ProviderDefinition.Setup {
        provider.definition.setup ?? .fallback(for: name, error: lastError)
    }

    public var readsUsage: Bool { usageHistory?.hasUsage == true }

    /// QUOTA health — the worst quota in its usage. A failed fetch is not a
    /// status: it is `lastError`, and the last usage stays.
    public var status: QuotaStatus { snapshot?.overallStatus ?? .healthy }

    /// Where the login lives, for a login added by its folder.
    public var folder: SignedInFolder? {
        guard !isDefault, let rule = provider.definition.accounts?.folder, let path = values[rule.savedAs] else { return nil }
        return SignedInFolder(url: URL(fileURLWithPath: path), madeBy: madeBy ?? .folder)
    }

    /// What its tightest quota has left, in percent — `nil` before a usage.
    public var percentLeft: Double? { snapshot?.lowestQuota?.percentRemaining }

    // MARK: - In use

    /// The login new terminal sessions of its product start with, when its
    /// product offers a choice of logins.
    public var isInUse: Bool { canBeInUse && provider.inUse?.login === self }

    /// Whether it can be chosen for new terminal sessions: its product offers
    /// a choice, and it is one of the logins offered.
    public var canBeInUse: Bool {
        guard let inUse = provider.inUse, inUse.offersChoice else { return false }
        return inUse.logins.contains { $0 === self }
    }

    /// *Use for new sessions*.
    public func useForNewSessions() throws {
        guard let inUse = provider.inUse else {
            throw UsageError.executionFailed("\(provider.name) can't choose a login for new sessions.")
        }
        try inUse.use(self)
    }

    /// The email the data source reported, else the one it was added with.
    public var accountEmail: String? { snapshot?.accountEmail ?? email }

    /// What it is called: the name the person gave it, else its login's
    /// email, else the product's name.
    public var displayName: String {
        let given = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !given.isEmpty { return given }
        return accountEmail ?? provider.name
    }

    // MARK: - AIProvider (forwarded to the provider)

    /// The pill's name: the product's while this is the only login to tell
    /// apart, else the account's own.
    public var name: String { provider.hasSeveralAccounts ? displayName : provider.name }

    public var cliCommand: String { provider.definition.cli ?? "" }
    /// The dashboard for the plan the last usage reported (#328).
    public var dashboardURL: URL? {
        provider.definition.profile.links.dashboard(for: snapshot?.accountTier, settings: provider.settingFills(for: self))
    }
    public var statusPageURL: URL? { provider.definition.profile.links.status }
    public var backgroundRefreshFloor: Duration? { provider.backgroundRefreshFloor }
    /// Guest passes are read with the default login's CLI, so only it has them.
    public var guestPasses: GuestPasses? { isDefault ? provider.guestPasses : nil }
    /// What this login used, day by day, from its own logs — `nil` when the
    /// provider offers no usage history, or doesn't say where an added
    /// login's logs are.
    public var usageHistory: UsageHistory? { provider.usageHistory(for: self) }

    public func isAvailable() async -> Bool {
        await provider.isAvailable(self)
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        try await provider.refresh(self, .interactive)
    }

    @discardableResult
    public func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot {
        try await provider.refresh(self, kind)
    }

    public func hasKey(for kind: String) -> Bool {
        provider.hasKey(for: kind, account: self)
    }

    // MARK: - Recording a fetch (the provider's)

    func succeed(_ usage: UsageSnapshot, from kind: String) -> UsageSnapshot {
        snapshot = usage
        lastError = nil
        lastFailedStep = nil
        answeredBy = kind
        return usage
    }

    /// Some of its data sources failed while others answered (`together`):
    /// the usage they gave stays, and the failure shows beside it as fetch
    /// health — never wiping what was seen.
    func noteFailure(_ error: Error) {
        if let failure = error as? DataSourceError {
            lastError = failure.reason
            lastFailedStep = failure.step
        } else {
            lastError = error
            lastFailedStep = nil
        }
    }

    func fail(_ error: Error) {
        if let failure = error as? DataSourceError {
            lastError = failure.reason
            lastFailedStep = failure.step
        } else {
            lastError = error
            lastFailedStep = nil
        }
        // An added login that is signed out shows nothing rather than its
        // last usage, which would read as still current.
        if !isDefault, let tag = (lastError as? UsageError)?.tag,
           tag == "authenticationRequired" || tag == "sessionExpired" {
            snapshot = nil
        }
    }
}
