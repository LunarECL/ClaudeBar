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

    public let id: String
    public let name: String
    public let cliCommand: String
    public var dashboardURL: URL? { definition.links.dashboard }
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

    public init(
        definition: ProviderDefinition,
        dataSources: [DataSource],
        settings: any ProviderSettingsRepository,
        dailyUsage: (any DailyUsageAnalyzing)? = nil,
        guestPasses: GuestPasses? = nil
    ) {
        self.definition = definition
        self.id = definition.id
        self.name = definition.name
        self.cliCommand = definition.cli ?? ""
        self.dataSources = dataSources
        self.dailyUsage = dailyUsage
        self.guestPasses = guestPasses
        self.settings = settings
        self.isEnabled = settings.isEnabled(forProvider: definition.id, defaultValue: definition.enabledByDefault)
    }

    /// The data source in use: the one the person picked, else the default.
    public var activeKind: String {
        if let chosen = settings.dataSourceKind(forProvider: id), dataSource(chosen) != nil {
            return chosen
        }
        return definition.defaultDataSource
    }

    /// Switches the data source. `false` when the provider has no such one.
    @discardableResult
    public func use(_ kind: String) -> Bool {
        guard dataSource(kind) != nil else { return false }
        settings.setDataSourceKind(kind, forProvider: id)
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
        guard var current = dataSource(activeKind) else {
            throw ProbeError.noData
        }
        isSyncing = true
        defer { isSyncing = false }

        var tried: Set = [current.kind]
        var reported: Error?
        while true {
            do {
                let usage = try await current.fetchUsage()
                return succeed(await withDailyUsage(usage, kind), from: current.kind)
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

    // MARK: - Private

    private func dataSource(_ kind: String) -> DataSource? {
        dataSources.first { $0.kind == kind }
    }

    /// The fallback a data source names, unless a provider setting turns it off.
    private func enabledFallback(of source: DataSource) -> DataSource? {
        guard let fallback = source.definition.fallback else { return nil }
        if let setting = fallback.enabledBySetting, settings.isOn(setting, forProvider: id) == false {
            return nil
        }
        return dataSource(fallback.to)
    }

    private func withDailyUsage(_ usage: UsageSnapshot, _ kind: RefreshKind) async -> UsageSnapshot {
        guard kind == .interactive,
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
    }

    private static func reason(of error: Error) -> ProbeError? {
        (error as? DataSourceError)?.reason ?? (error as? ProbeError)
    }
}
