import Testing
import Foundation
@testable import Infrastructure

@Suite
struct OpenRouterSettingsRepositoryTests {
    @Test
    func `user defaults repository persists and removes OpenRouter settings`() {
        let suiteName = "OpenRouterSettingsRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

        #expect(repository.openrouterAuthEnvVar().isEmpty)
        #expect(repository.hasOpenRouterApiKey() == false)

        repository.setOpenRouterAuthEnvVar("CUSTOM_OPENROUTER_KEY")
        repository.saveOpenRouterApiKey("sk-or-test")

        #expect(repository.openrouterAuthEnvVar() == "CUSTOM_OPENROUTER_KEY")
        #expect(repository.getOpenRouterApiKey() == "sk-or-test")
        #expect(repository.hasOpenRouterApiKey() == true)

        repository.deleteOpenRouterApiKey()
        #expect(repository.getOpenRouterApiKey() == nil)
        #expect(repository.hasOpenRouterApiKey() == false)
    }

    @Test
    func `JSON repository persists and removes OpenRouter settings`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenRouterJSONSettingsTests.\(UUID().uuidString)")
        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let suiteName = "OpenRouterJSONCredentialsTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            credentials.removePersistentDomain(forName: suiteName)
        }
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: settingsURL),
            credentials: credentials
        )

        #expect(repository.openrouterAuthEnvVar().isEmpty)
        #expect(repository.hasOpenRouterApiKey() == false)

        repository.setOpenRouterAuthEnvVar("CUSTOM_OPENROUTER_KEY")
        repository.saveOpenRouterApiKey("sk-or-test")

        #expect(repository.openrouterAuthEnvVar() == "CUSTOM_OPENROUTER_KEY")
        #expect(repository.getOpenRouterApiKey() == "sk-or-test")
        #expect(repository.hasOpenRouterApiKey() == true)

        repository.deleteOpenRouterApiKey()
        #expect(repository.getOpenRouterApiKey() == nil)
        #expect(repository.hasOpenRouterApiKey() == false)
    }
}
