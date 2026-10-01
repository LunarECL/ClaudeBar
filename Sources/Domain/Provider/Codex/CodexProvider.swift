import Foundation
import Observation

/// Codex AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Supports dual probe modes: RPC (default) and API.
@MainActor
@Observable
public final class CodexProvider: AIProvider {
    // MARK: - Identity

    public nonisolated let account: ProviderAccount
    public nonisolated var id: String { account.id }
    public var accountEmail: String? { snapshot?.accountEmail ?? account.email }
    public var name: String { accountEmail ?? "Codex" }
    public let cliCommand: String = "codex"

    public var dashboardURL: URL? {
        URL(string: "https://platform.openai.com/usage")
    }

    public var statusPageURL: URL? {
        URL(string: "https://status.openai.com")
    }

    /// Whether the provider is enabled (persisted via settingsRepository)
    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State (Observable)

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    // MARK: - Probe Mode

    /// The current probe mode (RPC or API)
    public var probeMode: CodexProbeMode {
        get {
            if let codexSettings = settingsRepository as? CodexSettingsRepository {
                return codexSettings.codexProbeMode()
            }
            return .rpc
        }
        set {
            if let codexSettings = settingsRepository as? CodexSettingsRepository {
                codexSettings.setCodexProbeMode(newValue)
            }
        }
    }

    // MARK: - Internal

    /// The RPC probe for fetching usage data via `codex app-server`
    @ObservationIgnored private var refreshTask: Task<UsageSnapshot, Error>?

    private let rpcProbe: any UsageProbe

    /// The API probe for fetching usage data via HTTP API (optional)
    private let apiProbe: (any UsageProbe)?

    /// The settings repository for persisting provider settings
    private let settingsRepository: any ProviderSettingsRepository

    /// Whether an explicit user action (Refresh / Connect) has successfully
    /// probed the Codex CLI at least once. Read from the persisted
    /// `CodexSettingsRepository` flag at init and kept in sync locally, so a
    /// success on this run lifts the gate immediately (issue #216).
    private var hasVerifiedSession: Bool

    /// The message surfaced while the Codex CLI session has not been checked
    /// by an explicit user action yet (issue #216).
    static let notCheckedMessage = "Codex CLI session not checked. Click Refresh or Connect to check Codex status."

    /// Returns the active probe based on current mode
    private var activeProbe: any UsageProbe {
        switch probeMode {
        case .rpc:
            return rpcProbe
        case .api:
            // Fall back to RPC if API probe not available
            return apiProbe ?? rpcProbe
        }
    }

    /// Whether the active probe is the RPC probe — the only one with the
    /// spawn-a-subprocess side effect this gate exists for (issue #216).
    private var backgroundProbeIsRPC: Bool {
        switch probeMode {
        case .rpc:
            return true
        case .api:
            // Without an API probe the provider falls back to the RPC probe
            return apiProbe == nil
        }
    }

    // MARK: - Initialization

    /// Creates a Codex provider with RPC probe only (legacy initializer)
    /// - Parameters:
    ///   - probe: The RPC probe to use for fetching usage data
    ///   - settingsRepository: The repository for persisting settings
    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository,
                account: ProviderAccount = ProviderAccount(providerId: "codex", label: "")) {
        self.account = account
        self.rpcProbe = probe
        self.apiProbe = nil
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: account.id)
        self.hasVerifiedSession = Self.initialVerifiedSession(
            account: account,
            settingsRepository: settingsRepository as? CodexSettingsRepository
        )
    }

    /// Creates a Codex provider with both RPC and API probes
    /// - Parameters:
    ///   - rpcProbe: The RPC probe for fetching usage via `codex app-server`
    ///   - apiProbe: The API probe for fetching usage via HTTP API
    ///   - settingsRepository: The repository for persisting settings (must be CodexSettingsRepository for mode switching)
    public init(
        rpcProbe: any UsageProbe,
        apiProbe: any UsageProbe,
        settingsRepository: any CodexSettingsRepository,
        account: ProviderAccount = ProviderAccount(providerId: "codex", label: "")
    ) {
        self.account = account
        self.rpcProbe = rpcProbe
        self.apiProbe = apiProbe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: account.id)
        self.hasVerifiedSession = Self.initialVerifiedSession(account: account, settingsRepository: settingsRepository)
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await activeProbe.isAvailable()
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Interactive refresh: delegates to the kind-aware implementation.
    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        try await refresh(.interactive)
    }

    /// Refreshes the usage data and updates the snapshot.
    ///
    /// The RPC probe spawns `codex app-server`, and an unauthenticated Codex
    /// CLI can open the ChatGPT browser login all by itself. Probing is an
    /// active operation, so it only runs on `.interactive` refreshes — a
    /// genuine click (Refresh / Connect). Automatic refreshes stay passive
    /// until such a click has succeeded at least once: `.background` (the
    /// menu-bar poll) and `.passive` (popover open) return the last snapshot
    /// without spawning anything, or surface `notCheckedMessage` when there is
    /// nothing to show yet. A successful interactive refresh that ran the RPC
    /// probe persists the verified flag (issue #216).
    ///
    /// Concurrent refreshes of one account share a single probe, so
    /// overlapping UI and background polls cannot rotate its refresh token twice.
    @discardableResult
    public func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot {
        if kind != .interactive, backgroundProbeIsRPC, !hasVerifiedSession {
            if let snapshot {
                return snapshot
            }
            let error = ProbeError.executionFailed(Self.notCheckedMessage)
            lastError = error
            throw error
        }

        if let refreshTask { return try await refreshTask.value }
        let probe = activeProbe
        let account = account
        let task = Task {
            let value = try await probe.probe()
            return Self.identify(value, account: account)
        }
        refreshTask = task
        isSyncing = true
        defer {
            isSyncing = false
            refreshTask = nil
        }

        do {
            let newSnapshot = try await task.value
            snapshot = newSnapshot
            lastError = nil
            if kind == .interactive, backgroundProbeIsRPC {
                markSessionVerified()
            }
            return newSnapshot
        } catch {
            lastError = error
            if !account.isDefault, let error = error as? ProbeError,
               error == .authenticationRequired || error == .sessionExpired(hint: nil) {
                snapshot = nil
            }
            throw error
        }
    }

    private static func identify(_ value: UsageSnapshot, account: ProviderAccount) -> UsageSnapshot {
        UsageSnapshot(
            providerId: account.id,
            quotas: value.quotas.map { quota in
                UsageQuota(percentRemaining: quota.percentRemaining, quotaType: quota.quotaType,
                           providerId: account.id, resetsAt: quota.resetsAt, resetText: quota.resetText,
                           windowDuration: quota.windowDuration, dollarRemaining: quota.dollarRemaining,
                           dollarUsed: quota.dollarUsed, dollarCap: quota.dollarCap, group: quota.group,
                           compactTitle: quota.compactTitle, menuBarTitle: quota.menuBarTitle, currency: quota.currency)
            },
            capturedAt: value.capturedAt, accountEmail: value.accountEmail ?? account.email,
            accountOrganization: value.accountOrganization, loginMethod: value.loginMethod,
            accountTier: value.accountTier, costUsage: value.costUsage,
            bedrockUsage: value.bedrockUsage, dailyUsageReport: value.dailyUsageReport,
            extensionMetrics: value.extensionMetrics
        )
    }

    /// The default account reads the persisted flag. An added account was
    /// probed by the explicit add-account flow before it could exist, and its
    /// probe fails closed without credentials, so it starts verified.
    private static func initialVerifiedSession(
        account: ProviderAccount,
        settingsRepository: (any CodexSettingsRepository)?
    ) -> Bool {
        guard account.isDefault else { return true }
        return settingsRepository?.codexVerifiedAtLeastOnce() ?? false
    }

    /// Persists that the Codex CLI session was checked by an explicit user
    /// action, so later background refreshes may probe again (issue #216).
    private func markSessionVerified() {
        guard !hasVerifiedSession else { return }
        hasVerifiedSession = true
        (settingsRepository as? CodexSettingsRepository)?.setCodexVerifiedAtLeastOnce(true)
    }

    /// Whether API mode is available (API probe was provided)
    public var supportsApiMode: Bool {
        apiProbe != nil
    }
}
