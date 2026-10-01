import DataSources
import Quotas
import Foundation

/// The module's factory: definition → `Provider`, its data sources made live
/// by `DataSources.make`. The App composes with this and never names a worker.
public enum Providers {
    /// A built-in definition, shipped in this module's `Resources/Providers/`.
    public static func builtIn(_ id: String) throws -> ProviderDefinition {
        try ProviderDefinition.parse(try builtInData(id))
    }

    /// The built-in definition's JSON, as shipped.
    public static func builtInData(_ id: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: id, withExtension: "json") else {
            throw DefinitionError.missingFile(id)
        }
        return try Data(contentsOf: url)
    }

    /// A `{{account.…}}` the account's saved values did not fill.
    private static func hasUnfilledValue(_ source: DataSourceDefinition) -> Bool {
        guard let data = try? JSONEncoder().encode(source) else { return true }
        return String(decoding: data, as: UTF8.self).contains("{{account.")
    }

    /// A mapping script shipped beside the built-in definitions.
    public static let builtInScripts: DataSources.ScriptSource = { file in
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: name, withExtension: ext.isEmpty ? "js" : ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// A provider on the real network, CLI, Keychain and file system.
    @MainActor
    public static func make(
        _ definition: ProviderDefinition,
        settings: any ProviderSettingsRepository,
        dailyUsage: (any DailyUsageAnalyzing)? = nil,
        guestPasses: GuestPasses? = nil
    ) -> Provider {
        Provider(
            definition: definition,
            dataSources: definition.dataSources.map {
                DataSources.make($0, providerId: definition.id, scripts: builtInScripts)
            },
            settings: settings,
            dailyUsage: dailyUsage,
            guestPasses: guestPasses
        )
    }

    /// An added account of a built-in provider: the definition's
    /// `accounts.dataSources`, filled from the account's saved values. `nil`
    /// when the provider has no accounts or the saved values are incomplete.
    @MainActor
    public static func make(
        _ id: String,
        account: ProviderAccountConfig,
        settings: any ProviderSettingsRepository
    ) throws -> Provider? {
        guard account.accountId != ProviderAccount.defaultAccountId,
              let definition = try ProviderDefinition.parse(try builtInData(id), account: account.probeConfig),
              !definition.dataSources.contains(where: { Self.hasUnfilledValue($0) }) else { return nil }
        return Provider(
            definition: definition,
            dataSources: definition.dataSources.map {
                DataSources.make($0, providerId: definition.id, scripts: builtInScripts)
            },
            settings: settings,
            account: account.toProviderAccount(providerId: id)
        )
    }

    /// A built-in provider by id — `Providers.make("codex", settings:)`.
    @MainActor
    public static func make(
        _ id: String,
        settings: any ProviderSettingsRepository,
        dailyUsage: (any DailyUsageAnalyzing)? = nil,
        guestPasses: GuestPasses? = nil
    ) throws -> Provider {
        make(try builtIn(id), settings: settings, dailyUsage: dailyUsage, guestPasses: guestPasses)
    }
}
