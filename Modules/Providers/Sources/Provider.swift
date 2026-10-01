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
    private let settings: any ProviderSettingsRepository

    public init(definition: ProviderDefinition, dataSources: [DataSource], settings: any ProviderSettingsRepository) {
        self.definition = definition
        self.id = definition.id
        self.name = definition.name
        self.cliCommand = definition.cli ?? ""
        self.dataSources = dataSources
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

    public func isAvailable() async -> Bool {
        guard let active = dataSource(activeKind) else { return false }
        return await active.isReady()
    }

    /// Fetches with the active data source; when that fails, tries its
    /// fallback once. A failure keeps the last usage on screen.
    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        guard let active = dataSource(activeKind) else {
            throw ProbeError.noData
        }
        isSyncing = true
        defer { isSyncing = false }

        do {
            return succeed(try await active.fetchUsage(), from: active.kind)
        } catch let primary {
            if Self.mayFallBack(after: primary),
               let fallbackKind = active.definition.fallback,
               let fallback = dataSource(fallbackKind) {
                AppLog.probes.warning("\(id) \(active.kind) failed (\(primary.localizedDescription)), trying \(fallbackKind)")
                do {
                    return succeed(try await fallback.fetchUsage(), from: fallback.kind)
                } catch {
                    // Both failed: report the active one's failure — it is the
                    // root cause, and the fallback's would send the person
                    // chasing the wrong problem.
                    AppLog.probes.info("\(id) \(fallbackKind) fallback also failed: \(error.localizedDescription)")
                }
            }
            fail(primary)
            throw lastError ?? primary
        }
    }

    // MARK: - Private

    private func dataSource(_ kind: String) -> DataSource? {
        dataSources.first { $0.kind == kind }
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

    /// A rate limit is not a reason to hit another endpoint.
    private static func mayFallBack(after error: Error) -> Bool {
        let reason = (error as? DataSourceError)?.reason ?? (error as? ProbeError)
        if case .rateLimited? = reason { return false }
        return true
    }
}
