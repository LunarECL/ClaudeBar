import Domain
import Foundation

/// The vault custom providers read their keys from — ClaudeBar's credential
/// store, under `provider.<id>.<name>`. A definition names the key; the value
/// lives only here.
public struct ProviderVault: SecretVault {
    private let credentials: any CredentialRepository

    public init(credentials: any CredentialRepository = KeychainCredentialRepository.shared) {
        self.credentials = credentials
    }

    public func secret(_ name: String, provider: String) -> String? {
        credentials.get(forKey: Self.key(name, provider: provider))
    }

    public func save(_ value: String, _ name: String, provider: String) {
        credentials.save(value, forKey: Self.key(name, provider: provider))
    }

    @discardableResult
    public func delete(_ name: String, provider: String) -> Bool {
        credentials.delete(forKey: Self.key(name, provider: provider))
    }

    static func key(_ name: String, provider: String) -> String {
        "provider.\(provider).\(name)"
    }
}
