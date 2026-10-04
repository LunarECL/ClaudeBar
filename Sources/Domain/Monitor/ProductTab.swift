import Foundation
import Providers

/// A pill in the popover: one product, with every enabled login of it — so
/// three Claude logins are one *Claude* tab, side by side, not three tabs.
/// Its logins come in the order the person gave them.
@MainActor
public struct ProductTab: Identifiable {
    /// The product's id — `codex`, never `codex.<acct>`.
    public let id: String
    public let name: String
    /// Its logins in the lineup, in the person's order.
    public let accounts: [any AIProvider]

    /// The product behind a tab of logins; `nil` for a legacy provider.
    public var provider: Provider? { (accounts.first as? Account)?.provider }

    /// The product's switch: its own, or a legacy provider's (TARGET §12).
    public var isEnabled: Bool { provider?.isEnabled ?? accounts.first?.isEnabled ?? false }

    /// A login's name on the product's row — only when there are several to
    /// tell apart; one login is just the product.
    public func loginName(_ login: any AIProvider) -> String? {
        guard accounts.count > 1 else { return nil }
        return (login as? Account)?.displayName ?? login.name
    }

    /// What the product's page configures: its plain login, whose id the
    /// configuration is keyed by — or a legacy provider itself.
    public var page: (any AIProvider)? { provider?.defaultAccount ?? accounts.first }

    public func contains(_ lineupId: String) -> Bool {
        accounts.contains { $0.id == lineupId }
    }

    /// The lineup as tabs, in the order products first appear in it.
    public static func tabs(of lineup: [any AIProvider]) -> [ProductTab] {
        var tabs: [ProductTab] = []
        var seen: Set<String> = []
        for member in lineup {
            guard let account = member as? Account else {
                tabs.append(ProductTab(id: member.id, name: member.name, accounts: [member]))
                continue
            }
            let product = account.provider
            guard seen.insert(product.id).inserted else { continue }
            let shown = Set(lineup.map(\.id))
            let accounts: [any AIProvider] = product.accounts.filter { shown.contains($0.id) }
            tabs.append(ProductTab(id: product.id, name: product.name, accounts: accounts))
        }
        return tabs
    }
}
