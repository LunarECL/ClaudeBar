import DataSources
import Diagnostics
import Domain
import Foundation
import Observation

/// THE lifecycle — one class for every provider. Everything a provider used to
/// re-implement (the enabled toggle, the syncing flag, the last usage, the last
/// error, the probe mode, the fallback) lives here once; what a provider *is*
/// lives in its definition, and how it fetches lives in its data sources.
@MainActor
@Observable
public final class Provider: AIProvider {
    public let definition: ProviderDefinition

    // MARK: - Identity

    /// Which login this is — the default one, or one the person added.
    public nonisolated let account: ProviderAccount
    /// `codex` for the default login, `codex.<account>` for an added one.
    public let id: String
    public let cliCommand: String

    /// The account's email when the definition names providers by it, else the product.
    public var name: String {
        guard definition.accounts?.nameFromEmail == true, let accountEmail else { return definition.name }
        return accountEmail
    }

    public var accountEmail: String? { snapshot?.accountEmail ?? account.email }

    /// Whether this provider is named by its account — what the menu bar and
    /// the popover show beside its usage.
    public var isNamedByAccount: Bool { definition.accounts?.nameFromEmail == true }
    /// The dashboard for the plan the last usage reported (#328: an API
    /// account's is Console billing, a subscription's claude.ai usage).
    public var dashboardURL: URL? { definition.links.dashboard(for: snapshot?.accountTier) }
    public var statusPageURL: URL? { definition.links.status }

    public var isEnabled: Bool {
        didSet { settings.setEnabled(isEnabled, forProvider: id) }
    }

    // MARK: - State

    public private(set) var isSyncing = false
    public private(set) var snapshot: UsageSnapshot?
    /// Today's `ProbeError`, so every screen that reads one keeps reading one.
    public private(set) var lastError: Error?
    /// Which step failed last — lookup, fetch or mapping. `nil` after a success.
    public private(set) var lastFailedStep: DataSourceError.Step?
    /// The kind of the data source that produced `snapshot` — *via RPC*.
    public private(set) var answeredBy: String?

    // MARK: - Data sources

    public let dataSources: [DataSource]
    /// Today's and yesterday's usage, read on an interactive refresh only —
    /// a background poll stays cheap (#204).
    public let dailyUsage: (any DailyUsageAnalyzing)?
    /// *Share Claude Code*, for a provider whose plan can issue guest passes.
    public let guestPasses: GuestPasses?
    private let settings: any ProviderSettingsRepository
    @ObservationIgnored private var refreshTask: Task<UsageSnapshot, Error>?

    public init(
        definition: ProviderDefinition,
        dataSources: [DataSource],
        settings: any ProviderSettingsRepository,
        account: ProviderAccount? = nil,
        dailyUsage: (any DailyUsageAnalyzing)? = nil,
        guestPasses: GuestPasses? = nil
    ) {
        let account = account ?? ProviderAccount(providerId: definition.id, label: "")
        self.definition = definition
        self.account = account
        self.id = account.id
        self.cliCommand = definition.cli ?? ""
        self.dataSources = dataSources
        self.dailyUsage = dailyUsage
        self.guestPasses = guestPasses
        self.settings = settings
        self.isEnabled = settings.isEnabled(forProvider: account.id, defaultValue: definition.enabledByDefault)
    }

    /// The data source in use: the one the person picked, else the default.
    /// One choice covers every account of the provider.
    public var activeKind: String {
        if let chosen = settings.dataSourceKind(forProvider: definition.id), dataSource(chosen) != nil {
            return chosen
        }
        return definition.defaultDataSource
    }

    /// Switches the data source. `false` when the provider has no such one.
    @discardableResult
    public func use(_ kind: String) -> Bool {
        guard dataSource(kind) != nil else { return false }
        settings.setDataSourceKind(kind, forProvider: definition.id)
        return true
    }

    /// Whether a data source's key lookup finds a key — what a config card
    /// shows as *credentials found*. `false` when there is no such data source.
    public func hasKey(for kind: String) -> Bool {
        dataSource(kind)?.hasKey ?? false
    }

    // MARK: - AIProvider

    /// Ready when the active data source is — or, failing that, the fallback
    /// it would hand over to.
    public func isAvailable() async -> Bool {
        guard let active = dataSource(activeKind) else { return false }
        if await active.isReady() { return true }
        guard let fallback = enabledFallback(of: active) else { return false }
        return await fallback.isReady()
    }

    /// A data source that serves cached usage sets how often the background
    /// may ask (Claude's API: 15 minutes, #204).
    public var backgroundRefreshFloor: Duration? {
        dataSource(activeKind)?.cacheTTL.map { .seconds($0) }
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        try await refresh(.interactive)
    }

    /// Fetches with the active data source and follows its hand-offs and
    /// fallback until one answers. A failure keeps the last usage on screen
    /// and reports the first real failure — not a hand-off, and not a
    /// fallback's, which would send the person chasing the wrong problem.
    @discardableResult
    public func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot {
        guard let active = dataSource(activeKind) else {
            throw ProbeError.noData
        }
        // Held back until one explicit refresh succeeded (#216): a CLI that
        // was never signed in may open a browser login on its own.
        if kind != .interactive, active.definition.verifyBeforeBackground, !isVerified {
            if let snapshot { return snapshot }
            let error = ProbeError.executionFailed(active.definition.unverifiedMessage ?? "Not checked yet. Click Refresh.")
            lastError = error
            throw error
        }
        // Overlapping refreshes share one result.
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await run(from: active, kind) }
        refreshTask = task
        defer { refreshTask = nil }
        let usage = try await task.value
        if kind == .interactive, active.definition.verifyBeforeBackground {
            markVerified()
        }
        return usage
    }

    // MARK: - Private

    private func run(from start: DataSource, _ kind: RefreshKind) async throws -> UsageSnapshot {
        var current = start
        isSyncing = true
        defer { isSyncing = false }

        var tried: Set = [current.kind]
        var reported: Error?
        while true {
            do {
                let usage = try await current.fetchUsage()
                return succeed(identified(await withDailyUsage(usage, kind)), from: current.kind)
            } catch {
                let reason = Self.reason(of: error)
                if case .rateLimited? = reason {
                    // A rate limit is not a reason to hit another endpoint.
                    reported = reported ?? error
                    break
                }
                if let tag = reason?.tag, let next = current.definition.fallbackOn[tag],
                   !tried.contains(next), let handOff = dataSource(next) {
                    AppLog.probes.info("\(id) \(current.kind) handed off to \(next) (\(tag))")
                    tried.insert(next)
                    current = handOff
                    continue
                }
                reported = reported ?? error
                if let fallback = enabledFallback(of: current), !tried.contains(fallback.kind) {
                    AppLog.probes.warning("\(id) \(current.kind) failed (\(error.localizedDescription)), trying \(fallback.kind)")
                    tried.insert(fallback.kind)
                    current = fallback
                    continue
                }
                break
            }
        }
        if let reported, tried.count > 1 {
            AppLog.probes.info("\(id): every data source failed; reporting \(reported.localizedDescription)")
        }
        fail(reported ?? ProbeError.noData)
        throw lastError ?? ProbeError.noData
    }

    /// An added account is checked by being added; the default login once
    /// an explicit refresh succeeds, remembered as `<id>.verifiedAtLeastOnce`.
    private var isVerified: Bool {
        !account.isDefault || settings.isOn("verifiedAtLeastOnce", forProvider: definition.id) == true
    }

    private func markVerified() {
        guard !isVerified else { return }
        settings.setOn(true, "verifiedAtLeastOnce", forProvider: definition.id)
    }

    /// The usage as this account's: its id on every quota, its saved email
    /// when the source named none.
    private func identified(_ usage: UsageSnapshot) -> UsageSnapshot {
        guard usage.providerId != id || (usage.accountEmail == nil && account.email != nil) else { return usage }
        return UsageSnapshot(
            providerId: id,
            quotas: usage.quotas.map { quota in
                UsageQuota(
                    percentRemaining: quota.percentRemaining, quotaType: quota.quotaType, providerId: id,
                    resetsAt: quota.resetsAt, resetText: quota.resetText, windowDuration: quota.windowDuration,
                    dollarRemaining: quota.dollarRemaining, dollarUsed: quota.dollarUsed, dollarCap: quota.dollarCap,
                    group: quota.group, compactTitle: quota.compactTitle, menuBarTitle: quota.menuBarTitle,
                    currency: quota.currency
                )
            },
            capturedAt: usage.capturedAt,
            accountEmail: usage.accountEmail ?? account.email,
            accountOrganization: usage.accountOrganization,
            loginMethod: usage.loginMethod,
            accountTier: usage.accountTier,
            costUsage: usage.costUsage,
            bedrockUsage: usage.bedrockUsage,
            dailyUsageReport: usage.dailyUsageReport,
            extensionMetrics: usage.extensionMetrics
        )
    }

    private func dataSource(_ kind: String) -> DataSource? {
        dataSources.first { $0.kind == kind }
    }

    /// The fallback a data source names, unless a provider setting turns it off.
    private func enabledFallback(of source: DataSource) -> DataSource? {
        guard let fallback = source.definition.fallback else { return nil }
        if let setting = fallback.enabledBySetting, settings.isOn(setting, forProvider: definition.id) == false {
            return nil
        }
        return dataSource(fallback.to)
    }

    private func withDailyUsage(_ usage: UsageSnapshot, _ kind: RefreshKind) async -> UsageSnapshot {
        guard kind != .background,
              let dailyUsage,
              let report = try? await dailyUsage.analyzeToday(),
              !report.today.isEmpty || !report.previous.isEmpty else {
            return usage
        }
        return UsageSnapshot(
            providerId: usage.providerId,
            quotas: usage.quotas,
            capturedAt: usage.capturedAt,
            accountEmail: usage.accountEmail,
            accountOrganization: usage.accountOrganization,
            loginMethod: usage.loginMethod,
            accountTier: usage.accountTier,
            costUsage: usage.costUsage,
            bedrockUsage: usage.bedrockUsage,
            dailyUsageReport: report,
            extensionMetrics: usage.extensionMetrics
        )
    }

    private func succeed(_ usage: UsageSnapshot, from kind: String) -> UsageSnapshot {
        snapshot = usage
        lastError = nil
        lastFailedStep = nil
        answeredBy = kind
        return usage
    }

    private func fail(_ error: Error) {
        if let failure = error as? DataSourceError {
            lastError = failure.reason
            lastFailedStep = failure.step
        } else {
            lastError = error
            lastFailedStep = nil
        }
        // An added account that is signed out shows nothing rather than its
        // last usage, which would read as still current.
        if !account.isDefault, let tag = (lastError as? ProbeError)?.tag,
           tag == "authenticationRequired" || tag == "sessionExpired" {
            snapshot = nil
        }
    }

    private static func reason(of error: Error) -> ProbeError? {
        (error as? DataSourceError)?.reason ?? (error as? ProbeError)
    }
}
