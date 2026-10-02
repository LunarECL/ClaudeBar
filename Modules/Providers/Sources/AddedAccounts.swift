import DataSources
import Quotas
import Foundation

/// *Add Account…*: checks a folder a second login lives in
/// (`accounts.folder` in the definition) and returns what to save — the folder
/// and the login's account id; the credentials stay where the CLI keeps them.
/// `provider.add(_:)` then runs it.
public enum AddedAccounts {
    /// Checks a chosen folder and returns the account to save: the folder
    /// holds a login, it is not the default login, and it is not listed yet.
    public static func configuration(
        _ providerId: String,
        folder: String,
        existing: [ProviderAccountConfig],
        defaultFolder: String? = nil,
        makeDataSource: ((DataSourceDefinition) -> DataSource)? = nil
    ) throws -> ProviderAccountConfig {
        let definition = try Providers.builtIn(providerId)
        guard let rule = definition.accounts?.folder else {
            throw UsageError.executionFailed("\(definition.profile.name) has no added accounts.")
        }
        let make = makeDataSource ?? { DataSources.make($0, providerId: providerId) }
        let home = resolved(folder)
        let defaultHome = (defaultFolder ?? rule.default).map { resolved(DataSources.expandPath($0)) }
        guard home != defaultHome else {
            throw UsageError.executionFailed("This is the default \(definition.profile.name) login, which is already listed.")
        }
        let login = try Login(definition, folder: home, rule: rule, make: make)
        guard let accountId = login.accountId, let email = login.email else {
            throw UsageError.executionFailed(rule.notSignedIn ?? "No \(definition.profile.name) login found in this folder.")
        }
        let defaultAccountId = try defaultHome.flatMap { try Login(definition, folder: $0, rule: rule, make: make).accountId }
        let listed = existing.contains {
            $0.probeConfig[rule.accountId.savedAs] == accountId
                || $0.probeConfig[rule.savedAs].map(resolved) == home
        }
        guard accountId != defaultAccountId, !listed else {
            throw UsageError.executionFailed("This \(definition.profile.name) account is already listed.")
        }
        return ProviderAccountConfig(
            accountId: UUID().uuidString.lowercased(), label: "", email: email,
            probeConfig: rule.values(for: home).merging([rule.accountId.savedAs: accountId]) { _, id in id }
        )
    }

    // MARK: - Private

    /// What the account's data sources would read in a folder: the first one
    /// that looks up a credential, filled with the folder. A folder whose key
    /// does not answer holds no login, whatever else it holds.
    private struct Login {
        let accountId: String?
        let email: String?

        init(
            _ definition: ProviderDefinition,
            folder: String,
            rule: ProviderDefinition.Accounts.Folder,
            make: (DataSourceDefinition) -> DataSource
        ) throws {
            let values = rule.values(for: folder).merging([rule.accountId.savedAs: ""]) { _, empty in empty }
            guard let source = try definition.dataSources(forAccount: values).first(where: { $0.credential != nil }) else {
                accountId = nil
                email = nil
                return
            }
            let live = make(source)
            guard live.hasKey else {
                accountId = nil
                email = nil
                return
            }
            accountId = live.fact(rule.accountId.fact).flatMap { $0.isEmpty ? nil : $0 }
            email = live.fact(rule.email)
        }
    }

    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
