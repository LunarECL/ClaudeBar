import Providers
import Quotas
import Foundation

/// A settings repository that keeps everything in memory — the real behaviour
/// a `Provider` relies on, without touching `~/.claudebar/settings.json`.
final class InMemoryProviderSettings: ProviderSettingsRepository, @unchecked Sendable {
    private var enabled: [String: Bool] = [:]
    private var kinds: [String: String] = [:]
    private var cardURLs: [String: String] = [:]
    /// `"<provider>.<setting>"` → on/off, as `settings.json` keeps them.
    private var flags: [String: Bool]

    init(dataSourceKinds: [String: String] = [:], flags: [String: Bool] = [:]) {
        self.kinds = dataSourceKinds
        self.flags = flags
    }

    func isOn(_ setting: String, forProvider id: String) -> Bool? {
        flags["\(id).\(setting)"]
    }

    func setOn(_ on: Bool, _ setting: String, forProvider id: String) {
        flags["\(id).\(setting)"] = on
    }

    func isEnabled(forProvider id: String) -> Bool {
        enabled[id] ?? true
    }

    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        enabled[id] ?? defaultValue
    }

    func setEnabled(_ enabled: Bool, forProvider id: String) {
        self.enabled[id] = enabled
    }

    func customCardURL(forProvider id: String) -> String? {
        cardURLs[id]
    }

    func setCustomCardURL(_ url: String?, forProvider id: String) {
        cardURLs[id] = url
    }

    func dataSourceKind(forProvider id: String) -> String? {
        kinds[id]
    }

    func setDataSourceKind(_ kind: String, forProvider id: String) {
        kinds[id] = kind
    }
}
