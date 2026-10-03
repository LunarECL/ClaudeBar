import Foundation
import Domain

/// Probes the OpenRouter API for credit information.
/// OpenRouter is pay-per-use and exposes no percentage/window quota — only a
/// monetary credit balance via `GET https://openrouter.ai/api/v1/credits`.
/// Authentication: Bearer token from env var or stored API key.
public struct OpenRouterUsageProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let settingsRepository: any OpenRouterSettingsRepository
    private let timeout: TimeInterval
    /// Reads an environment variable by name. Injected so tests are
    /// deterministic regardless of the host environment.
    private let environmentValue: @Sendable (String) -> String?

    /// The OpenRouter credits endpoint
    static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        settingsRepository: any OpenRouterSettingsRepository,
        timeout: TimeInterval = 30,
        environmentValue: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) {
        self.networkClient = networkClient
        self.settingsRepository = settingsRepository
        self.timeout = timeout
        self.environmentValue = environmentValue
    }

    // MARK: - Token Resolution

    func getApiKey() -> String? {
        // First, check environment variable if configured
        let envVarName = settingsRepository.openrouterAuthEnvVar()
        let effectiveEnvVar = envVarName.isEmpty ? "OPENROUTER_API_KEY" : envVarName
        if let envValue = environmentValue(effectiveEnvVar), !envValue.isEmpty {
            AppLog.probes.debug("OpenRouter: Using API key from env var '\(effectiveEnvVar)'")
            return envValue
        }

        // Fall back to stored API key
        if let storedKey = settingsRepository.getOpenRouterApiKey(), !storedKey.isEmpty {
            AppLog.probes.debug("OpenRouter: Using stored API key")
            return storedKey
        }

        return nil
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        let hasKey = getApiKey() != nil
        if !hasKey {
            AppLog.probes.debug("OpenRouter: Not available - no API key configured")
        }
        return hasKey
    }

    public func probe() async throws -> UsageSnapshot {
        guard let apiKey = getApiKey(), !apiKey.isEmpty else {
            AppLog.probes.error("OpenRouter: No API key configured (check env var or settings)")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.info("Starting OpenRouter probe...")

        var request = URLRequest(url: Self.creditsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            AppLog.probes.error("OpenRouter API returned HTTP \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ProbeError.authenticationRequired
            }
            throw ProbeError.executionFailed("OpenRouter API returned HTTP \(httpResponse.statusCode)")
        }

        // Log raw response at debug level, never including the Authorization header
        if let responseText = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("OpenRouter API response: \(responseText.prefix(500))")
        }

        let snapshot = try Self.parseResponse(data, providerId: "openrouter")

        AppLog.probes.info("OpenRouter probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(quota.formattedDollarRemaining ?? "n/a") remaining")
        }

        return snapshot
    }

    // MARK: - Response Parsing (Static for testability)

    /// Parses the OpenRouter credits response into a UsageSnapshot.
    /// OpenRouter reports a monetary credit balance with no percentage cap, so the
    /// quota uses `dollarRemaining` with `percentRemaining` pinned to 100 (DeepSeek pattern).
    /// The remaining balance is `total_credits - total_usage`.
    static func parseResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let decoder = JSONDecoder()

        let response: OpenRouterCreditsResponse
        do {
            response = try decoder.decode(OpenRouterCreditsResponse.self, from: data)
        } catch {
            AppLog.probes.error("OpenRouter parse failed: Invalid JSON - \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("OpenRouter raw response: \(rawString.prefix(500))")
            }
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        guard let credits = response.data else {
            AppLog.probes.error("OpenRouter: Missing data object in response")
            throw ProbeError.noData
        }

        // The API returns amounts as strings, but tolerate numbers too.
        let total = credits.totalCredits.value
        let used = credits.totalUsage.value

        let remaining = total - used

        // Credits have no cap → percent is 100 while there is money left. When
        // usage has overrun the balance the credit can't be spent, so surface
        // the quota as depleted.
        let percentRemaining: Double = remaining > 0 ? 100 : 0
        let quota = UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: .modelSpecific("Credits"),
            providerId: providerId,
            resetText: breakdownText(total: total, used: used),
            dollarRemaining: remaining,
            currency: "USD"
        )

        return UsageSnapshot(
            providerId: providerId,
            quotas: [quota],
            capturedAt: Date()
        )
    }

    // MARK: - Formatting

    /// Builds the "Total: $10.00 · Used: $3.00" breakdown subtitle.
    static func breakdownText(total: Decimal, used: Decimal) -> String {
        "Total: \(formatAmount(total)) · Used: \(formatAmount(used))"
    }

    static func formatAmount(_ amount: Decimal) -> String {
        String(
            format: "%@%.2f",
            UsageQuota.currencySymbol(for: "USD"),
            NSDecimalNumber(decimal: amount).doubleValue
        )
    }
}

// MARK: - Response Models (Private)

private struct OpenRouterCreditsResponse: Decodable {
    let data: OpenRouterCredits?
}

private struct OpenRouterCredits: Decodable {
    /// Amounts arrive as strings (e.g. "10.00"); tolerate bare numbers too.
    let totalCredits: FlexibleDecimal
    let totalUsage: FlexibleDecimal

    private enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }
}

/// A Decodable wrapper that accepts a JSON number or a JSON string holding a number.
/// Mirrors the private helper in VercelUsageProbe.
private struct FlexibleDecimal: Decodable {
    let value: Decimal

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let number = try? container.decode(Decimal.self) {
            value = number
            return
        }

        let string = try container.decode(String.self)
        guard let number = Decimal(
            string: string,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a decimal number or numeric string"
            )
        }
        value = number
    }
}
