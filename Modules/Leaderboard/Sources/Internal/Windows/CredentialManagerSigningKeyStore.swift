#if os(Windows)
import Diagnostics
import Foundation
import WinSDK

/// The key in Windows Credential Manager: a generic credential, its blob the
/// key's raw bytes, kept on this PC only (`CRED_PERSIST_LOCAL_MACHINE`): other
/// sessions of the same person on this PC read it, and it never roams to
/// another PC with the account. There is no plain-file fallback.
struct CredentialManagerSigningKeyStore: SigningKeyStore {
    var target = "com.tddworks.claudebar/leaderboard-signing-key"

    func load() -> Data? {
        var credential: PCREDENTIALW?
        let found = target.withCString(encodedAs: UTF16.self) { name in
            CredReadW(name, DWORD(CRED_TYPE_GENERIC), 0, &credential)
        }
        guard found, let credential else {
            let error = GetLastError()
            if error != DWORD(ERROR_NOT_FOUND) { logFailure("read", error) }
            return nil
        }
        defer { CredFree(credential) }
        guard let blob = credential.pointee.CredentialBlob else { return nil }
        return Data(bytes: blob, count: Int(credential.pointee.CredentialBlobSize))
    }

    func save(_ rawKey: Data) {
        var name = Array(target.utf16) + [0]
        var blob = [UInt8](rawKey)
        let saved = name.withUnsafeMutableBufferPointer { name in
            blob.withUnsafeMutableBufferPointer { blob in
                var credential = CREDENTIALW()
                credential.`Type` = DWORD(CRED_TYPE_GENERIC)
                credential.TargetName = name.baseAddress
                credential.CredentialBlobSize = DWORD(blob.count)
                credential.CredentialBlob = blob.baseAddress
                credential.Persist = DWORD(CRED_PERSIST_LOCAL_MACHINE)
                return CredWriteW(&credential, 0)
            }
        }
        guard saved else { return logFailure("save", GetLastError()) }
    }

    func delete() {
        let deleted = target.withCString(encodedAs: UTF16.self) { name in
            CredDeleteW(name, DWORD(CRED_TYPE_GENERIC), 0)
        }
        guard deleted else {
            let error = GetLastError()
            if error != DWORD(ERROR_NOT_FOUND) { logFailure("delete", error) }
            return
        }
    }

    private func logFailure(_ operation: String, _ error: DWORD) {
        AppLog.credentials.error("Credential Manager \(operation) failed with error \(error)")
    }
}
#endif
