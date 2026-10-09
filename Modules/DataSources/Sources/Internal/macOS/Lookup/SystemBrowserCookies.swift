#if os(macOS)
import Foundation
import SweetCookieKit

/// The real stores, read with SweetCookieKit.
public struct SystemBrowserCookies: BrowserCookieReading {
    public init() {}

    public func stores(domains: [String], names: [String]) -> [[BrowserCookie]] {
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: domains, domainMatch: .suffix, includeExpired: false)
        var found: [[BrowserCookie]] = []
        for browser in Browser.defaultImportOrder {
            guard let stores = try? client.records(matching: query, in: browser) else { continue }
            for store in stores {
                let cookies = store.cookies(origin: query.origin)
                    .filter { names.contains($0.name) }
                    .map { BrowserCookie(name: $0.name, value: $0.value) }
                if !cookies.isEmpty { found.append(cookies) }
            }
        }
        return found
    }
}
#endif
