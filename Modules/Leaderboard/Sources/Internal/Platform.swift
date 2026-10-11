import Foundation

/// What this machine offers the leaderboard (MODULAR_DESIGN §10, "One place
/// picks the platform"): where it keeps the key's private half, how it reads
/// the machine, and what a person calls it. Each platform folder defines
/// `current` once; only the factory and the error texts read it.
struct Platform: Sendable {
    /// What a person calls this kind of machine, as in "this Mac" or "this PC".
    var deviceName: String
    /// Where the key's private half is kept.
    var signingKeyStore: any SigningKeyStore
    /// The machine, read from its hardware.
    var machineIdentity: any MachineIdentity
}
