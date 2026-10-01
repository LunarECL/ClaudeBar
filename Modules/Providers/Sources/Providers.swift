import DataSources
import Domain
import Foundation

/// The module's factory: definition → `Provider`, its data sources made live
/// by `DataSources.make`. The App composes with this and never names a worker.
public enum Providers {
    /// A built-in definition, shipped in this module's `Resources/Providers/`.
    public static func builtIn(_ id: String) throws -> ProviderDefinition {
        guard let url = Bundle.module.url(forResource: id, withExtension: "json") else {
            throw DefinitionError.missingFile(id)
        }
        return try ProviderDefinition.parse(Data(contentsOf: url))
    }

    /// A provider on the real network, CLI and file system.
    @MainActor
    public static func make(_ definition: ProviderDefinition, settings: any ProviderSettingsRepository) -> Provider {
        Provider(
            definition: definition,
            dataSources: definition.dataSources.map { DataSources.make($0, providerId: definition.id) },
            settings: settings
        )
    }

    /// A built-in provider by id — `Providers.make("codex", settings:)`.
    @MainActor
    public static func make(_ id: String, settings: any ProviderSettingsRepository) throws -> Provider {
        make(try builtIn(id), settings: settings)
    }
}
