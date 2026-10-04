import Foundation
import Providers

/// The *In use* records kept in memory: what the shell would read after
/// switching, without touching `~/.claudebar`.
final class InMemoryLoginsInUse: LoginsInUse, @unchecked Sendable {
    private let lock = NSLock()
    private var folders: [String: URL] = [:]

    init(_ existing: [String: URL] = [:]) {
        folders = existing
    }

    func folder(for providerId: String) -> URL? {
        lock.withLock { folders[providerId] }
    }

    func use(_ folder: URL?, for providerId: String) throws {
        lock.withLock { folders[providerId] = folder?.standardizedFileURL }
    }
}
