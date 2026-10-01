import DataSources
import Quotas
import Foundation

/// *Add Account…*: a second login of a provider, added by choosing the folder
/// it lives in (`accounts.folder` in the definition). Only the folder and the
/// login's account id are saved; the credentials stay where the CLI keeps them.
public enum AddedAccounts {
    /// Checks a chosen folder and returns the account to save: the folder
    /// holds a login, it is not the default login, and it is not listed yet.
    public static func configuration(
        _ providerId: String,
        folder: String,
        existing: [ProviderAccountConfig],
        defaultFolder: String? = nil
    ) throws -> ProviderAccountConfig {
        let definition = try Providers.builtIn(providerId)
        guard let rule = definition.accounts?.folder else {
            throw UsageError.executionFailed("\(definition.name) has no added accounts.")
        }
        let home = resolved(folder)
        let defaultHome = (defaultFolder ?? rule.default).map { resolved(DataSources.expandPath($0)) }
        guard home != defaultHome else {
            throw UsageError.executionFailed("This is the default \(definition.name) login, which is already listed.")
        }
        let facts = try loginFacts(providerId, folder: home, rule: rule)
        guard let accountId = facts[rule.accountId.fact], !accountId.isEmpty, let email = facts["email"] else {
            throw UsageError.executionFailed(rule.notSignedIn ?? "No \(definition.name) login found in this folder.")
        }
        let defaultAccountId = try defaultHome.flatMap { try loginFacts(providerId, folder: $0, rule: rule)[rule.accountId.fact] }
        let listed = existing.contains {
            $0.probeConfig[rule.accountId.savedAs] == accountId
                || $0.probeConfig[rule.savedAs].map(resolved) == home
        }
        guard accountId != defaultAccountId, !listed else {
            throw UsageError.executionFailed("This \(definition.name) account is already listed.")
        }
        return ProviderAccountConfig(
            accountId: UUID().uuidString.lowercased(), label: "", email: email,
            probeConfig: [rule.savedAs: home, rule.accountId.savedAs: accountId]
        )
    }

    /// The provider an added account runs as — `nil` for the default login
    /// or saved values the definition can't run with.
    @MainActor
    public static func provider(
        _ providerId: String,
        configuration: ProviderAccountConfig,
        settings: any ProviderSettingsRepository
    ) -> Provider? {
        try? Providers.make(providerId, account: configuration, settings: settings)
    }

    // MARK: - Private

    /// What the account's data sources would read in `folder` — the non-secret
    /// values of the first one that looks up a credential.
    private static func loginFacts(
        _ providerId: String,
        folder: String,
        rule: ProviderDefinition.Accounts.Folder
    ) throws -> [String: String] {
        let values = [rule.savedAs: folder, rule.accountId.savedAs: ""]
        guard let definition = try ProviderDefinition.parse(try Providers.builtInData(providerId), account: values),
              let source = definition.dataSources.first(where: { $0.credential != nil }) else { return [:] }
        return DataSources.make(source, providerId: providerId).credentialFacts()
    }

    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
