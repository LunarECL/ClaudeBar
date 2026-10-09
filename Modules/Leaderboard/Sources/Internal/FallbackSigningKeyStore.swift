import Diagnostics
import Foundation

/// The leaderboard key's private half, kept like Notify!'s token: the secure
/// store first, read back to prove it landed, and the fallback when the secure
/// store refuses it, as the Keychain refuses a locally built, ad-hoc signed
/// app. Never `settings.json`, never logged.
struct FallbackSigningKeyStore: SigningKeyStore {
    let secure: any SigningKeyStore
    let fallback: any SigningKeyStore

    func load() -> Data? {
        secure.load() ?? fallback.load()
    }

    func save(_ rawKey: Data) {
        secure.save(rawKey)
        if secure.load() == rawKey {
            fallback.delete()
            return
        }
        AppLog.credentials.warning("Leaderboard key could not be stored in the Keychain, keeping it in the app credential store instead")
        fallback.save(rawKey)
    }

    func delete() {
        secure.delete()
        fallback.delete()
    }
}
