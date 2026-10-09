import Mockable

/// Finds a CLI by name, as this platform finds the programs a person runs
/// (MODULAR_DESIGN §6, §10). The Mac's asks the login shell and the common
/// install folders; Windows' reads `PATH` and `PATHEXT`.
@Mockable
protocol BinaryLocating: Sendable {
    /// The CLI's full path, or `nil` when it isn't installed.
    func locate(_ cli: String) -> String?
}
