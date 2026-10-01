import Quotas
import DataSources
import Providers
import Foundation

/// Compact email labels for the limited menu-bar space. If truncation would
/// make two accounts indistinguishable, retain their complete addresses.
public enum CodexAccountLabel {
    public static func compact(_ email: String, among emails: [String]) -> String {
        let candidate = abbreviated(email)
        let collisions = Set(emails.filter { abbreviated($0) == candidate })
        return collisions.count > 1 ? email : candidate
    }

    private static func abbreviated(_ email: String) -> String {
        guard email.count > 22 else { return email }
        return String(email.prefix(12)) + "…" + String(email.suffix(9))
    }
}
