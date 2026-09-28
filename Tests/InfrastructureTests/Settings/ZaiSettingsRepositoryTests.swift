import Testing
import Foundation
@testable import Infrastructure

@Suite
struct ZaiSettingsRepositoryTests {
    @Test
    func `user defaults repository persists and removes Z.ai API key`() {
        let suiteName = "ZaiSettingsRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

        #expect(repository.hasZaiApiKey() == false)
        #expect(repository.getZaiApiKey() == nil)

        repository.saveZaiApiKey("glm-test-key")

        #expect(repository.getZaiApiKey() == "glm-test-key")
        #expect(repository.hasZaiApiKey() == true)

        repository.deleteZaiApiKey()
        #expect(repository.getZaiApiKey() == nil)
        #expect(repository.hasZaiApiKey() == false)
    }

    @Test
    func `JSON repository persists and removes Z.ai API key`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZaiJSONSettingsTests.\(UUID().uuidString)")
        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let suiteName = "ZaiJSONCredentialsTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            credentials.removePersistentDomain(forName: suiteName)
        }
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: settingsURL),
            credentials: credentials
        )

        #expect(repository.hasZaiApiKey() == false)
        #expect(repository.getZaiApiKey() == nil)

        repository.saveZaiApiKey("glm-test-key")

        #expect(repository.getZaiApiKey() == "glm-test-key")
        #expect(repository.hasZaiApiKey() == true)

        repository.deleteZaiApiKey()
        #expect(repository.getZaiApiKey() == nil)
        #expect(repository.hasZaiApiKey() == false)
    }

    @Test
    func `saving a new key replaces the previous Z.ai API key`() {
        let suiteName = "ZaiSettingsRepositoryReplaceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

        repository.saveZaiApiKey("glm-old-key")
        repository.saveZaiApiKey("glm-new-key")

        #expect(repository.getZaiApiKey() == "glm-new-key")
    }
}
