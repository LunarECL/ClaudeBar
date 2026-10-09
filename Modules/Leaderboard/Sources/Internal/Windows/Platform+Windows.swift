#if os(Windows)
import Foundation

extension Platform {
    /// ClaudeBar for Windows so far (MODULAR_DESIGN §10): it counts and signs a
    /// day as the Mac does, and keeps no key yet. Phase 3 keeps it in
    /// Credential Manager.
    static let current = Platform(signingKeyStore: nil)
}
#endif
