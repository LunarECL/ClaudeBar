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

    /// A mapping script shipped beside the built-in definitions.
    public static let builtInScripts: DataSources.ScriptSource = { file in
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: name, withExtension: ext.isEmpty ? "js" : ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// A provider on the real network, CLI, Keychain and file system, with
    /// its default login and every login in `accounts`.
    @MainActor
    public static func make(
        _ definition: ProviderDefinition,
        settings: any ProviderSettingsRepository,
        accounts: [ProviderAccountConfig] = [],
        dailyUsage: (any DailyUsageAnalyzing)? = nil,
        guestPasses: GuestPasses? = nil
    ) -> Provider {
        Provider(
            definition: definition,
            settings: settings,
            accounts: accounts,
            makeDataSource: { DataSources.make($0, providerId: definition.id, scripts: builtInScripts) },
            dailyUsage: dailyUsage,
            guestPasses: guestPasses
        )
    }

    /// A built-in provider by id — `Providers.make("codex", settings:)`.
    @MainActor
    public static func make(
        _ id: String,
        settings: any ProviderSettingsRepository,
        accounts: [ProviderAccountConfig] = [],
        dailyUsage: (any DailyUsageAnalyzing)? = nil,
        guestPasses: GuestPasses? = nil
    ) throws -> Provider {
        make(try builtIn(id), settings: settings, accounts: accounts, dailyUsage: dailyUsage, guestPasses: guestPasses)
    }
}
