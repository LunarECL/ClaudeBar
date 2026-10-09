import Foundation

/// The key in the app's UserDefaults, as base64: where it stays when the
/// Keychain refuses it. The name is the one the app's credential store gave
/// it, so a key kept there before the `Leaderboard` module still loads.
final class DefaultsSigningKeyStore: SigningKeyStore, @unchecked Sendable {
    static let name = "com.claudebar.credentials.leaderboard-signing-key"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Data? {
        defaults.string(forKey: Self.name).flatMap { Data(base64Encoded: $0) }
    }

    func save(_ rawKey: Data) {
        defaults.set(rawKey.base64EncodedString(), forKey: Self.name)
    }

    func delete() {
        defaults.removeObject(forKey: Self.name)
    }
}
