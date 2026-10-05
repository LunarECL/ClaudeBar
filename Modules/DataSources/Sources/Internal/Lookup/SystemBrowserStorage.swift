import Foundation
import SweetCookieKit

/// The real stores: each Chromium profile's `Local Storage/leveldb`, found
/// beside its cookies and read with SweetCookieKit.
public struct SystemBrowserStorage: BrowserStorageReading {
    public init() {}

    public func stores(origin: String) -> [[String: String]] {
        let client = BrowserCookieClient()
        var seen = Set<String>()
        var found: [[String: String]] = []
        for browser in Browser.defaultImportOrder where browser.usesChromiumProfileStore {
            for store in client.stores(for: browser) {
                guard let profile = Self.profileFolder(of: store), seen.insert(profile.path).inserted else { continue }
                let leveldb = profile.appendingPathComponent("Local Storage/leveldb", isDirectory: true)
                guard FileManager.default.fileExists(atPath: leveldb.path) else { continue }
                let entries = ChromiumLocalStorageReader.readEntries(for: origin, in: leveldb)
                guard !entries.isEmpty else { continue }
                found.append(Dictionary(entries.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first }))
            }
        }
        return found
    }

    /// The profile folder a cookie store lives in: `…/Default/Cookies` or
    /// `…/Default/Network/Cookies`.
    private static func profileFolder(of store: BrowserCookieStore) -> URL? {
        guard let database = store.databaseURL else { return nil }
        let folder = database.deletingLastPathComponent()
        return folder.lastPathComponent == "Network" ? folder.deletingLastPathComponent() : folder
    }
}
