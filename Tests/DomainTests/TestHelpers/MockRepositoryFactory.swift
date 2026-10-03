import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Shared test helper factory for creating mock/test repositories
/// Eliminates duplication across provider tests (CopilotProvider, BedrockProvider, etc.)
struct MockRepositoryFactory {

    /// Creates a mock settings repository for provider tests (base ProviderSettingsRepository)
    /// - Parameter enabled: Whether the provider is enabled (defaults to true)
    /// - Returns: A configured MockProviderSettingsRepository
    static func makeSettingsRepository(enabled: Bool = true) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(enabled)
        given(mock).isEnabled(forProvider: .any).willReturn(enabled)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        given(mock).customCardURL(forProvider: .any).willReturn(nil)
        given(mock).setCustomCardURL(.any, forProvider: .any).willReturn()
        return mock
    }

    /// Creates a Copilot settings repository for tests using isolated UserDefaults
    /// - Parameter enabled: Whether the provider is enabled (defaults to false for Copilot)
    /// - Parameter copilotAuthEnvVar: The Copilot auth env var
    /// - Parameter username: The GitHub username (empty = none)
    /// - Parameter hasToken: Whether a token is saved
    /// - Returns: A UserDefaultsProviderSettingsRepository with test suite
    static func makeCopilotSettingsRepository(
        enabled: Bool = false,
        copilotAuthEnvVar: String = "",
        username: String = "",
        hasToken: Bool = false
    ) -> UserDefaultsProviderSettingsRepository {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let repo = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        repo.setEnabled(enabled, forProvider: "copilot")
        if !copilotAuthEnvVar.isEmpty {
            repo.setCopilotAuthEnvVar(copilotAuthEnvVar)
        }
        if !username.isEmpty {
            repo.saveGithubUsername(username)
        }
        if hasToken {
            repo.saveGithubToken("test-token-\(UUID().uuidString)")
        }
        return repo
    }
}
