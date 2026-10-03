import Quotas
import DataSources
import Foundation
import Mockable
import Providers

/// Copilot-specific settings repository, extending base ProviderSettingsRepository.
/// Includes both configuration and credentials for GitHub Copilot.
/// Tests can use UserDefaultsProviderSettingsRepository with test UserDefaults.
/// App uses UserDefaultsProviderSettingsRepository.
public protocol CopilotSettingsRepository: ProviderSettingsRepository {
    // MARK: - Probe Mode

    /// Gets the probe mode for Copilot (billing or copilotAPI)
    func copilotProbeMode() -> CopilotProbeMode

    /// Sets the probe mode for Copilot
    func setCopilotProbeMode(_ mode: CopilotProbeMode)

    // MARK: - Configuration

    /// Gets the environment variable name for GitHub Copilot token (empty = no env fallback)
    func copilotAuthEnvVar() -> String

    /// Sets the environment variable name for GitHub Copilot token
    func setCopilotAuthEnvVar(_ envVar: String)

    // MARK: - Monthly Limit

    /// Gets the monthly premium request limit for Copilot (nil = use default of 50 for Free/Pro)
    func copilotMonthlyLimit() -> Int?

    /// Sets the monthly premium request limit for Copilot
    func setCopilotMonthlyLimit(_ limit: Int?)

    // MARK: - Manual Usage Override (for org-based subscriptions)

    /// Gets the manually entered usage value (nil = use API data)
    /// Can be either a request count or percentage depending on `copilotManualUsageIsPercent()`
    func copilotManualUsageValue() -> Double?

    /// Sets the manually entered usage value
    func setCopilotManualUsageValue(_ value: Double?)

    /// Gets whether the manual usage value is a percentage (true) or request count (false)
    func copilotManualUsageIsPercent() -> Bool

    /// Sets whether the manual usage value is a percentage
    func setCopilotManualUsageIsPercent(_ isPercent: Bool)

    /// Gets whether manual override is enabled (controlled externally, not auto-enabled)
    func copilotManualOverrideEnabled() -> Bool

    /// Sets whether manual override is enabled (must be controlled externally)
    func setCopilotManualOverrideEnabled(_ enabled: Bool)

    /// Gets whether the API returned empty data (persisted state)
    func copilotApiReturnedEmpty() -> Bool

    /// Sets whether the API returned empty data
    func setCopilotApiReturnedEmpty(_ empty: Bool)

    // MARK: - Usage Period Tracking

    /// Gets the last known usage period month (1-12)
    func copilotLastUsagePeriodMonth() -> Int?

    /// Gets the last known usage period year
    func copilotLastUsagePeriodYear() -> Int?

    /// Sets the last known usage period
    func setCopilotLastUsagePeriod(month: Int, year: Int)

    // MARK: - Credentials

    /// Saves the GitHub token
    func saveGithubToken(_ token: String)

    /// Retrieves the GitHub token
    func getGithubToken() -> String?

    /// Deletes the GitHub token
    func deleteGithubToken()

    /// Checks if a GitHub token is saved
    func hasGithubToken() -> Bool

    /// Saves the GitHub username
    func saveGithubUsername(_ username: String)

    /// Retrieves the GitHub username
    func getGithubUsername() -> String?

    /// Deletes the GitHub username
    func deleteGithubUsername()
}

/// Bedrock-specific settings repository, extending base ProviderSettingsRepository.
/// Stores AWS profile name (not credentials) and region configuration.
/// Tests can use UserDefaultsProviderSettingsRepository with test UserDefaults.
/// App uses UserDefaultsProviderSettingsRepository.
public protocol BedrockSettingsRepository: ProviderSettingsRepository {
    // MARK: - AWS Profile

    /// Gets the AWS profile name (empty = use default profile)
    func awsProfileName() -> String

    /// Sets the AWS profile name
    func setAWSProfileName(_ name: String)

    // MARK: - Regions

    /// Gets the list of AWS regions to monitor for Bedrock usage
    func bedrockRegions() -> [String]

    /// Sets the list of AWS regions to monitor
    func setBedrockRegions(_ regions: [String])

    // MARK: - Budget

    /// Gets the daily budget for quota calculations (nil = no budget set)
    func bedrockDailyBudget() -> Decimal?

    /// Sets the daily budget for quota calculations
    func setBedrockDailyBudget(_ amount: Decimal?)
}

/// Claude-specific settings repository, extending base ProviderSettingsRepository.
/// Includes configuration for probe mode (CLI vs API).
/// Tests can use UserDefaultsProviderSettingsRepository with test UserDefaults.
/// App uses UserDefaultsProviderSettingsRepository.
public protocol ClaudeSettingsRepository: ProviderSettingsRepository {
    /// Gets the probe mode for Claude (CLI or API)
    func claudeProbeMode() -> ClaudeProbeMode

    /// Sets the probe mode for Claude
    func setClaudeProbeMode(_ mode: ClaudeProbeMode)

    /// Whether to fall back to the CLI probe when the OAuth API probe is unavailable.
    /// Defaults to true. Disable to prevent `claude /usage` from running in API mode.
    func claudeCliFallbackEnabled() -> Bool

    /// Sets whether CLI fallback is enabled in API mode
    func setClaudeCliFallbackEnabled(_ enabled: Bool)
}

/// Codex-specific settings repository, extending base ProviderSettingsRepository.
/// Includes configuration for probe mode (RPC vs API).
/// Tests can use UserDefaultsProviderSettingsRepository with test UserDefaults.
/// App uses UserDefaultsProviderSettingsRepository.
public protocol CodexSettingsRepository: ProviderSettingsRepository {
    /// Gets the probe mode for Codex (RPC or API)
    func codexProbeMode() -> CodexProbeMode

    /// Sets the probe mode for Codex
    func setCodexProbeMode(_ mode: CodexProbeMode)

    /// Whether the Codex CLI session was successfully checked at least once by
    /// an explicit user action (Refresh / Connect). Until this is set, automatic
    /// background refreshes must not run the RPC probe: spawning `codex
    /// app-server` while the CLI is unauthenticated can open the ChatGPT browser
    /// login on its own (issue #216).
    func codexVerifiedAtLeastOnce() -> Bool

    /// Marks (or clears) the verified-at-least-once flag
    func setCodexVerifiedAtLeastOnce(_ verified: Bool)
}

/// DeepSeek-specific settings repository, extending base ProviderSettingsRepository.
/// Stores the API key and env-var name for DeepSeek balance monitoring.
public protocol DeepSeekSettingsRepository: ProviderSettingsRepository {
    /// Gets the environment variable name for DeepSeek API key (empty = use default DEEPSEEK_API_KEY)
    func deepseekAuthEnvVar() -> String

    /// Sets the environment variable name for DeepSeek API key
    func setDeepSeekAuthEnvVar(_ envVar: String)

    /// Saves the DeepSeek API key (for Settings UI input)
    func saveDeepSeekApiKey(_ key: String)

    /// Retrieves the DeepSeek API key
    func getDeepSeekApiKey() -> String?

    /// Deletes the DeepSeek API key
    func deleteDeepSeekApiKey()

    /// Checks if a DeepSeek API key is saved
    func hasDeepSeekApiKey() -> Bool
}

/// Alibaba Coding Plan-specific settings repository, extending base ProviderSettingsRepository.
/// Stores region, cookie source, manual cookie, and API key for Alibaba Coding Plan quota monitoring.
public protocol AlibabaSettingsRepository: ProviderSettingsRepository {
    /// Gets the API region (international or chinaMainland, default: international)
    func alibabaRegion() -> AlibabaRegion

    /// Sets the API region
    func setAlibabaRegion(_ region: AlibabaRegion)

    /// Gets the cookie source (auto from browser or manual)
    func alibabaCookieSource() -> AlibabaCookieSource

    /// Sets the cookie source
    func setAlibabaCookieSource(_ source: AlibabaCookieSource)

    /// Saves a manually entered cookie string
    func saveAlibabaManualCookie(_ cookie: String)

    /// Retrieves the manually entered cookie string
    func getAlibabaManualCookie() -> String?

    /// Saves the Alibaba API key
    func saveAlibabaApiKey(_ key: String)

    /// Retrieves the Alibaba API key
    func getAlibabaApiKey() -> String?

    /// Deletes the Alibaba API key
    func deleteAlibabaApiKey()

    /// Checks if an Alibaba API key is saved
    func hasAlibabaApiKey() -> Bool
}

