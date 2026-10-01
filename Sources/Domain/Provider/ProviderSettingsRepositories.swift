import Quotas
import DataSources
import Foundation
import Mockable
import Providers

/// Z.ai-specific settings repository, extending base ProviderSettingsRepository.
/// Tests can use UserDefaultsProviderSettingsRepository with test UserDefaults.
/// App uses UserDefaultsProviderSettingsRepository.
public protocol ZaiSettingsRepository: ProviderSettingsRepository {
    /// Gets the custom config path for Z.ai (empty string = use default)
    func zaiConfigPath() -> String

    /// Sets the custom config path for Z.ai
    func setZaiConfigPath(_ path: String)

    /// Gets the environment variable name for GLM auth token (empty = no env fallback)
    func glmAuthEnvVar() -> String

    /// Sets the environment variable name for GLM auth token
    func setGlmAuthEnvVar(_ envVar: String)

    /// Saves the Z.ai GLM API key (for Settings UI input)
    func saveZaiApiKey(_ key: String)

    /// Retrieves the Z.ai GLM API key
    func getZaiApiKey() -> String?

    /// Deletes the Z.ai GLM API key
    func deleteZaiApiKey()

    /// Checks if a Z.ai GLM API key is saved
    func hasZaiApiKey() -> Bool
}

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
/// Includes configuration for probe mode (CLI vs API) and the CLI binary to execute.
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

    /// Gets the custom Claude CLI binary (empty string = use the default "claude").
    /// A real binary path or a PATH-resolvable name works; shell aliases and
    /// functions do not, because a subprocess can only exec a binary (#210).
    func claudeBinary() -> String

    /// Sets the custom Claude CLI binary (empty string to use the default "claude")
    func setClaudeBinary(_ binary: String)
}

public extension ClaudeSettingsRepository {
    /// The Claude CLI binary the probes should execute, resolving the user's
    /// setting: a configured path or name is used as-is (trimmed), and an unset,
    /// empty, or whitespace-only setting falls back to the default "claude".
    /// The value is passed to the CLI executor as a binary, never interpreted
    /// as a shell command line (#210).
    func resolvedClaudeBinary() -> String {
        let trimmed = claudeBinary().trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "claude" : trimmed
    }
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

/// Kimi-specific settings repository, extending base ProviderSettingsRepository.
/// Includes configuration for probe mode (CLI vs API).
/// Tests can use UserDefaultsProviderSettingsRepository with test UserDefaults.
/// App uses UserDefaultsProviderSettingsRepository.
public protocol KimiSettingsRepository: ProviderSettingsRepository {
    /// Gets the probe mode for Kimi (CLI or API)
    func kimiProbeMode() -> KimiProbeMode

    /// Sets the probe mode for Kimi
    func setKimiProbeMode(_ mode: KimiProbeMode)

    /// Gets the API region (china or international, default: china for legacy compatibility)
    func kimiRegion() -> KimiRegion

    /// Sets the API region
    func setKimiRegion(_ region: KimiRegion)
}

/// MiniMax-specific settings repository, extending base ProviderSettingsRepository.
/// Stores API key and region configuration for MiniMax Coding Plan quota monitoring.
/// Tests can use UserDefaultsProviderSettingsRepository with test UserDefaults.
/// App uses UserDefaultsProviderSettingsRepository.
public protocol MiniMaxSettingsRepository: ProviderSettingsRepository {
    /// Gets the API region (international or china, default: china for legacy compatibility)
    /// (获取 API 区域设置，默认中国区以兼容旧版用户)
    func minimaxRegion() -> MiniMaxRegion

    /// Sets the API region (设置 API 区域)
    func setMinimaxRegion(_ region: MiniMaxRegion)

    /// Gets the environment variable name for MiniMax API key (empty = use default MINIMAX_API_KEY)
    func minimaxAuthEnvVar() -> String

    /// Sets the environment variable name for MiniMax API key
    func setMinimaxAuthEnvVar(_ envVar: String)

    /// Saves the MiniMax API key (for Settings UI input)
    func saveMinimaxApiKey(_ key: String)

    /// Retrieves the MiniMax API key
    func getMinimaxApiKey() -> String?

    /// Deletes the MiniMax API key
    func deleteMinimaxApiKey()

    /// Checks if a MiniMax API key is saved
    func hasMinimaxApiKey() -> Bool
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

/// Vercel AI Gateway-specific settings repository, extending base ProviderSettingsRepository.
/// Production settings use `JSONSettingsRepository`; the UserDefaults implementation
/// remains available as a legacy migration adapter and isolated test repository.
public protocol VercelSettingsRepository: ProviderSettingsRepository {
    /// Gets the environment variable name for the AI Gateway API key (empty = use default AI_GATEWAY_API_KEY)
    func vercelAuthEnvVar() -> String

    /// Sets the environment variable name for the AI Gateway API key
    func setVercelAuthEnvVar(_ envVar: String)

    /// Saves the AI Gateway API key (for Settings UI input)
    func saveVercelApiKey(_ key: String)

    /// Retrieves the AI Gateway API key
    func getVercelApiKey() -> String?

    /// Deletes the AI Gateway API key.
    /// - Returns: `true` when the credential is absent after the operation.
    @discardableResult
    func deleteVercelApiKey() -> Bool

    /// Checks if an AI Gateway API key is saved
    func hasVercelApiKey() -> Bool
}
