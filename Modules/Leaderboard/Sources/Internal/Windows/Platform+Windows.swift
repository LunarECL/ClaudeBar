#if os(Windows)
import Foundation

extension Platform {
    /// Windows: the key in Credential Manager, kept on this PC; the PC labelled
    /// as `WindowsMachineIdentity` says.
    static let current = Platform(
        deviceName: "PC",
        signingKeyStore: CredentialManagerSigningKeyStore(),
        machineIdentity: WindowsMachineIdentity()
    )
}

/// This PC as the leaderboard knows it: "Windows PC". The model Windows
/// reports is no label: a self-built PC reports its motherboard ("Z790 UD AC"),
/// so it isn't read. Neither is the computer's name, often a person's, nor
/// the machine GUID.
struct WindowsMachineIdentity: MachineIdentity {
    var model: DeviceLabel { DeviceLabel("Windows PC")! }
}
#endif
