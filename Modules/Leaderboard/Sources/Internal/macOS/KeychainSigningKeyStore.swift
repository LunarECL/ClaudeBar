#if os(macOS)
import Diagnostics
import Foundation
import Security

/// The key in the Keychain: a generic password, its value the key as base64.
/// The service, account and accessibility are the ones the app's credential
/// store used, so a member's key from before the `Leaderboard` module is the
/// same item and still loads.
struct KeychainSigningKeyStore: SigningKeyStore {
    var service = "com.tddworks.claudebar.credentials"
    var account = "leaderboard-signing-key"

    func load() -> Data? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound { logFailure("read", status) }
            return nil
        }
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }.flatMap { Data(base64Encoded: $0) }
    }

    func save(_ rawKey: Data) {
        let data = Data(rawKey.base64EncodedString().utf8)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { return logFailure("update", updateStatus) }
        var item = baseQuery
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus != errSecSuccess { logFailure("save", addStatus) }
    }

    func delete() {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { logFailure("delete", status) }
    }

    private var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private func logFailure(_ operation: String, _ status: OSStatus) {
        AppLog.credentials.error("Keychain credential \(operation) failed with status \(status)")
    }
}
#endif
