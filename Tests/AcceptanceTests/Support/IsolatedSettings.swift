import Foundation
@testable import Infrastructure

/// The settings the app keeps, in a `settings.json` of its own and with
/// secrets in throwaway defaults — never the person's settings or Keychain.
func isolatedSettings() -> JSONSettingsRepository {
    let id = UUID().uuidString
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-spec-\(id)/settings.json")
    let defaults = UserDefaults(suiteName: "com.claudebar.test.\(id)")!
    return JSONSettingsRepository(store: JSONSettingsStore(fileURL: file), credentials: defaults,
                                  secureCredentials: UserDefaultsCredentialRepository(defaults: defaults))
}
