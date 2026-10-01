import Foundation

/// The vault — keys a person gave ClaudeBar for a provider (*API KEY*). A
/// definition names a key (`"credential": { "setting": "apiKey" }`); the key
/// itself lives here, never in a definition, `settings.json`, a log line or an
/// exported file.
public protocol SecretStore: Sendable {
    /// The saved value of `name` for a provider, or `nil` when none is saved.
    func secret(_ name: String, provider: String) -> String?
}
