import Foundation
import Domain
import Mockable

// MARK: - Internal Protocol (for testability)

/// Internal protocol for sending system alerts. Enables testing without UNUserNotificationCenter.
@Mockable
protocol AlertSender: Sendable {
    func requestPermission() async -> Bool
    func send(title: String, body: String, categoryIdentifier: String) async throws
    /// A notification with one button, which opens `link`.
    func send(title: String, body: String, categoryIdentifier: String, button: String, link: URL) async throws
}

// MARK: - NotificationAlerter

/// Alerts users when their AI quota status degrades.
/// Sends system notifications for warning, critical, and depleted states.
public final class NotificationAlerter: QuotaAlerter, @unchecked Sendable {

    private let alertSender: AlertSender
    private let accountSettings: (any MultiAccountSettingsRepository)?

    /// Public initializer - uses system alerts
    public init(accountSettings: (any MultiAccountSettingsRepository)? = nil) {
        self.accountSettings = accountSettings
        self.alertSender = SystemAlertSender()
    }

    /// Internal initializer for testing
    init(alertSender: AlertSender, accountSettings: (any MultiAccountSettingsRepository)? = nil) {
        self.accountSettings = accountSettings
        self.alertSender = alertSender
    }

    // MARK: - Public API

    /// Requests permission to send quota alerts.
    public func requestPermission() async -> Bool {
        AppLog.notifications.debug("Requesting alert permission...")
        let granted = await alertSender.requestPermission()
        AppLog.notifications.info("Alert permission: \(granted ? "granted" : "denied")")
        return granted
    }

    // MARK: - QuotaAlerter

    public func alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) async {
        AppLog.notifications.debug("Status change: \(providerId) \(previousStatus) -> \(currentStatus)")

        // Only alert on degradation (getting worse)
        guard currentStatus > previousStatus else {
            AppLog.notifications.debug("Status improved or same, skipping alert")
            return
        }

        guard shouldAlert(for: currentStatus) else {
            AppLog.notifications.debug("Status \(currentStatus) does not require alert")
            return
        }

        let providerName = providerDisplayName(for: providerId)
        let title = "\(providerName) Quota Alert"
        let body = alertBody(for: currentStatus, providerName: providerName)

        AppLog.notifications.notice("Sending quota alert for \(providerId): \(currentStatus)")

        do {
            try await alertSender.send(title: title, body: body, categoryIdentifier: "QUOTA_ALERT")
            AppLog.notifications.info("Alert sent successfully")
        } catch {
            AppLog.notifications.error("Failed to send alert: \(error.localizedDescription)")
        }
    }

    // MARK: - In use

    /// The category of *In use* notifications; its button opens the alert's link.
    public static let inUseCategory = "IN_USE"

    public func inUse(_ alert: InUseAlert) async {
        let left = { (value: Int?) in value.map { " is at \($0)%" } ?? " is low" }
        let (title, body, button): (String, String, String) = switch alert.kind {
        case .worthSwitching:
            ("\(alert.providerName): \(alert.from)\(left(alert.fromLeft))",
             "\(alert.to) has \(alert.toLeft.map { "\($0)%" } ?? "more") left. Start new terminal sessions on \(alert.to)?",
             "Use for New Sessions")
        case .switched:
            ("New \(alert.providerName) sessions now use \(alert.to)",
             "\(alert.from)\(left(alert.fromLeft)). Sessions already running keep their login.",
             "Undo")
        }
        do {
            try await alertSender.send(title: title, body: body, categoryIdentifier: Self.inUseCategory, button: button, link: alert.link)
        } catch {
            AppLog.notifications.error("Failed to send the In use alert: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers (internal for testability)

    func shouldAlert(for status: QuotaStatus) -> Bool {
        switch status {
        case .warning, .critical, .depleted:
            return true
        case .healthy:
            return false
        }
    }

    func providerDisplayName(for providerId: String) -> String {
        if providerId.hasPrefix("codex."), let account = accountSettings?.accounts(forProvider: "codex")
            .first(where: { $0.toProviderAccount(providerId: "codex").id == providerId }) {
            return account.email.map { "Codex · \($0)" } ?? "Codex"
        }
        // A provider that is data names itself in its profile.
        if let definition = Providers.definition(forLineupId: providerId) {
            return definition.profile.name
        }
        switch providerId {
        default: return providerId.capitalized
        }
    }

    func alertBody(for status: QuotaStatus, providerName: String) -> String {
        switch status {
        case .warning:
            return "Your \(providerName) quota is running low. Consider pacing your usage."
        case .critical:
            return "Your \(providerName) quota is critically low! Save important work."
        case .depleted:
            return "Your \(providerName) quota is depleted. Usage may be blocked."
        case .healthy:
            return "Your \(providerName) quota has recovered."
        }
    }
}
