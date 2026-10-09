import Foundation
import Testing
@testable import Leaderboard

/// The private key beside the other secrets: in the Keychain, or the fallback
/// store when the Keychain refuses a locally built app.
@Suite
struct FallbackSigningKeyStoreTests {
    /// The Keychain as an ad-hoc signed build sees it: every call "succeeds", nothing is kept.
    private final class RefusingStore: SigningKeyStore, @unchecked Sendable {
        func load() -> Data? { nil }
        func save(_ rawKey: Data) {}
        func delete() {}
    }

    @Test func `should keep the signing key in the Keychain when the Keychain accepts it`() {
        let secure = InMemorySigningKeyStore()
        let fallback = InMemorySigningKeyStore()
        fallback.stored = Data([7])
        let store = FallbackSigningKeyStore(secure: secure, fallback: fallback)

        store.save(Data([1, 2, 3]))

        #expect(store.load() == Data([1, 2, 3]))
        #expect(secure.stored == Data([1, 2, 3]))
        #expect(fallback.stored == nil)
    }

    @Test func `should keep the signing key in the fallback store when the Keychain refuses it`() {
        let fallback = InMemorySigningKeyStore()
        let store = FallbackSigningKeyStore(secure: RefusingStore(), fallback: fallback)

        store.save(Data([1, 2, 3]))

        #expect(store.load() == Data([1, 2, 3]))
        #expect(fallback.stored == Data([1, 2, 3]))
    }

    @Test func `should forget the signing key from both stores when it is deleted`() {
        let secure = InMemorySigningKeyStore()
        let fallback = InMemorySigningKeyStore()
        secure.stored = Data([9])
        fallback.stored = Data([8])
        let store = FallbackSigningKeyStore(secure: secure, fallback: fallback)

        store.delete()

        #expect(store.load() == nil)
        #expect(secure.stored == nil && fallback.stored == nil)
    }

    /// A key the app's credential store kept in UserDefaults before the module
    /// is read under the same name and encoding, so the member keeps it.
    @Test func `should read a key the app kept in UserDefaults before the module`() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1, 2, 3]).base64EncodedString(), forKey: "com.claudebar.credentials.leaderboard-signing-key")

        #expect(DefaultsSigningKeyStore(defaults: defaults).load() == Data([1, 2, 3]))
    }
}
