import Foundation
import Mockable

/// A browser's local storage for one site — the port `browserStorage` reads
/// through. Values never enter a log.
@Mockable
public protocol BrowserStorageReading: Sendable {
    /// Every key and value the browsers keep for `origin`, one map per
    /// profile that has any, in the browsers' import order.
    func stores(origin: String) -> [[String: String]]
}

/// `browserStorage` — every value from the first browser profile that keeps
/// a token for the site; never one profile's token with another's values.
struct BrowserStorageReader: CredentialFinding {
    let query: BrowserStorageCredential
    let storage: any BrowserStorageReading

    func find() throws -> FoundCredential? {
        for store in storage.stores(origin: query.origin) {
            var values: [String: String] = [:]
            for (name, rule) in query.values {
                if let value = Self.value(rule, in: store) { values[name] = value }
            }
            guard let token = values["token"], !token.isEmpty else { continue }
            return FoundCredential(credential: Credential(values), save: nil)
        }
        return nil
    }

    /// The first key, in name order, the rule's pattern matches, read at its
    /// path when it has one; a JSON string is unquoted.
    private static func value(_ rule: BrowserStorageCredential.Value, in store: [String: String]) -> String? {
        let keys = store.keys.filter { fnmatch(rule.key, $0, 0) == 0 }.sorted()
        for key in keys {
            guard let raw = store[key] else { continue }
            let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed])
            let value: String?
            if let path = rule.path {
                value = (json as? [String: Any]).flatMap { CredentialDocument.values(["value": path], in: $0)["value"] }
            } else {
                value = json as? String ?? raw
            }
            if let value = value.map(Credential.trimmed), !value.isEmpty { return value }
        }
        return nil
    }
}
