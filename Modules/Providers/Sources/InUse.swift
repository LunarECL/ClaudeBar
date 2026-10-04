import Diagnostics
import Foundation
import Observation
import Quotas

/// *In use* — which of a product's logins new terminal sessions start with.
/// Only a product whose CLI can be started on a login's folder has one
/// (`Provider.inUse`). The choice is recorded as that folder, through
/// `LoginsInUse`, where the shell lines read it; running sessions keep theirs.
@MainActor
@Observable
public final class InUse {
    @ObservationIgnored private unowned let provider: Provider
    /// The command new sessions run, and the variable that points it at a folder.
    public let command: TerminalCommand
    /// *Switch when low* — the opt-in policy `review()` asks.
    public let switchWhenLow: SwitchWhenLow
    @ObservationIgnored private let record: any LoginsInUse
    private var loginId: String
    /// The suggestion already told — `<in use>><suggested>` — so a low is told once.
    @ObservationIgnored private var told: String?

    init(provider: Provider, command: TerminalCommand, record: any LoginsInUse, switchWhenLow: SwitchWhenLow) {
        self.provider = provider
        self.command = command
        self.record = record
        self.switchWhenLow = switchWhenLow
        self.loginId = provider.defaultAccount.id
        // A record naming a folder no login has is the plain login.
        if let folder = record.folder(for: provider.id),
           let chosen = provider.accounts.first(where: { $0.folder?.url.path == folder.standardizedFileURL.path }) {
            loginId = chosen.id
        }
    }

    /// The login new sessions start with — the plain login until another is chosen.
    public var login: Account {
        provider.accounts.first { $0.id == loginId } ?? provider.defaultAccount
    }

    /// The logins new sessions can start on: the plain login and every folder login.
    public var logins: [Account] {
        provider.accounts.filter { $0.isDefault || $0.folder != nil }
    }

    /// Whether there is a choice to offer: more than one login to start on.
    public var offersChoice: Bool { logins.count > 1 }

    /// *Use for new sessions* — records `account`'s folder, nothing for the plain login.
    public func use(_ account: Account) throws {
        guard logins.contains(where: { $0 === account }) else {
            throw UsageError.executionFailed("This login can't be used for new \(provider.name) sessions.")
        }
        try record.use(account.isDefault ? nil : account.folder?.url, for: provider.id)
        loginId = account.id
        AppLog.providers.info("\(provider.id): new sessions use \(account.isDefault ? "the plain login" : "an added login")")
    }

    /// The removed login was in use: new sessions go back to the plain login.
    func forget(_ account: Account) {
        guard loginId == account.id else { return }
        try? record.use(nil, for: provider.id)
        loginId = provider.defaultAccount.id
    }

    /// The login worth moving to: the one in use is critical or out, and
    /// another enabled login has more left — the most.
    public var worthSwitchingTo: Account? {
        let current = login
        guard current.status >= .critical, let left = current.percentLeft else { return nil }
        return logins
            .filter { $0 !== current && $0.isEnabled && ($0.percentLeft ?? -1) > left }
            .max { ($0.percentLeft ?? -1) < ($1.percentLeft ?? -1) }
    }

    /// What to tell the person after a refresh: that *Switch when low* moved
    /// new sessions, or — once per low — which login is worth moving to.
    public func review() throws -> InUseNotice? {
        let current = login
        if let next = switchWhenLow.next(from: current, among: logins) {
            try use(next)
            told = nil
            return .switched(from: current, to: next)
        }
        guard let better = worthSwitchingTo else {
            told = nil
            return nil
        }
        let pair = "\(current.id)>\(better.id)"
        guard told != pair else { return nil }
        told = pair
        return .worthSwitching(from: current, to: better)
    }
}

/// The command new terminal sessions run, and the variable that starts it on
/// a login's folder: `claude` with `CLAUDE_CONFIG_DIR`.
public struct TerminalCommand: Sendable, Equatable {
    public let name: String
    public let variable: String
    public let providerId: String

    public init(name: String, variable: String, providerId: String) {
        self.name = name
        self.variable = variable
        self.providerId = providerId
    }
}

/// What *In use* has to tell the person after a refresh.
public enum InUseNotice: Equatable {
    /// *Switch when low* moved new sessions from one login to another.
    case switched(from: Account, to: Account)
    /// The login in use is low and `to` has more left.
    case worthSwitching(from: Account, to: Account)

    public static func == (lhs: InUseNotice, rhs: InUseNotice) -> Bool {
        switch (lhs, rhs) {
        case let (.switched(a, b), .switched(c, d)), let (.worthSwitching(a, b), .worthSwitching(c, d)): a === c && b === d
        default: false
        }
    }
}
