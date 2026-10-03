import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct OpenRouterUsageProbeTests {

    // MARK: - Sample Data

    static let sampleApiResponse = """
    {
      "data": {
        "total_credits": "10.00",
        "total_usage": "3.00"
      }
    }
    """

    // MARK: - Helper

    /// Creates a probe with test UserDefaults and mock network client
    private func makeProbe(
        apiKey: String? = nil,
        envVar: String = "",
        environmentValue: @escaping @Sendable (String) -> String? = { _ in nil },
        networkClient: any NetworkClient = MockNetworkClient()
    ) -> OpenRouterUsageProbe {
        let defaults = UserDefaults(suiteName: "OpenRouterProbeTests.\(UUID().uuidString)")!
        let settingsRepository = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        settingsRepository.setOpenRouterAuthEnvVar(envVar)
        if let apiKey {
            settingsRepository.saveOpenRouterApiKey(apiKey)
        }
        return OpenRouterUsageProbe(
            networkClient: networkClient,
            settingsRepository: settingsRepository,
            environmentValue: environmentValue
        )
    }

    private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: OpenRouterUsageProbe.creditsURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns false when no API key`() async {
        // Given: no API key configured, no env var
        let probe = makeProbe()

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `isAvailable returns true when API key exists`() async {
        // Given
        let probe = makeProbe(apiKey: "test-key-123")

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns true when env var provides the key`() async {
        // Given: no stored key, but the default OPENROUTER_API_KEY env var is set
        let probe = makeProbe(environmentValue: { $0 == "OPENROUTER_API_KEY" ? "env-key" : nil })

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    // MARK: - probe Tests

    @Test
    func `probe returns UsageSnapshot on success`() async throws {
        // Given
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleApiResponse.utf8)
        let httpResponse = makeHTTPResponse(statusCode: 200)
        given(mockNetwork)
            .request(.any)
            .willReturn((responseData, httpResponse))

        let probe = makeProbe(apiKey: "test-key", networkClient: mockNetwork)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .modelSpecific("Credits"))
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(string: "7.00"))
        #expect(snapshot.providerId == "openrouter")
    }

    @Test
    func `probe sends Bearer and Accept headers to the credits endpoint`() async throws {
        // Given
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleApiResponse.utf8)
        let httpResponse = makeHTTPResponse(statusCode: 200)
        var capturedRequest: URLRequest?
        given(mockNetwork)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (responseData, httpResponse)
            }

        let probe = makeProbe(apiKey: "test-key", networkClient: mockNetwork)

        // When
        _ = try await probe.probe()

        // Then
        #expect(capturedRequest?.httpMethod == "GET")
        #expect(capturedRequest?.url?.absoluteString == "https://openrouter.ai/api/v1/credits")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test
    func `probe prefers env var over stored API key`() async throws {
        // Given: both a stored key and an env var exist; the env var must win
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleApiResponse.utf8)
        let httpResponse = makeHTTPResponse(statusCode: 200)
        var capturedRequest: URLRequest?
        given(mockNetwork)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (responseData, httpResponse)
            }

        let probe = makeProbe(
            apiKey: "stored-key",
            environmentValue: { $0 == "OPENROUTER_API_KEY" ? "env-key" : nil },
            networkClient: mockNetwork
        )

        // When
        _ = try await probe.probe()

        // Then
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer env-key")
    }

    @Test
    func `probe uses custom env var name from settings`() async throws {
        // Given: the settings name a non-default env var
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleApiResponse.utf8)
        let httpResponse = makeHTTPResponse(statusCode: 200)
        var capturedRequest: URLRequest?
        given(mockNetwork)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (responseData, httpResponse)
            }

        let probe = makeProbe(
            envVar: "MY_OPENROUTER_KEY",
            environmentValue: { $0 == "MY_OPENROUTER_KEY" ? "custom-env-key" : nil },
            networkClient: mockNetwork
        )

        // When
        _ = try await probe.probe()

        // Then
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer custom-env-key")
    }

    @Test
    func `probe throws authenticationRequired when no API key`() async {
        // Given: no key anywhere; the mock network has no stub, so any network
        // call would crash the test - proving none is made
        let probe = makeProbe()

        // When & Then
        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws authenticationRequired on HTTP 401`() async {
        // Given
        let mockNetwork = MockNetworkClient()
        let httpResponse = makeHTTPResponse(statusCode: 401)
        given(mockNetwork)
            .request(.any)
            .willReturn((Data(), httpResponse))

        let probe = makeProbe(apiKey: "bad-key", networkClient: mockNetwork)

        // When & Then
        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws authenticationRequired on HTTP 403`() async {
        // Given
        let mockNetwork = MockNetworkClient()
        let httpResponse = makeHTTPResponse(statusCode: 403)
        given(mockNetwork)
            .request(.any)
            .willReturn((Data(), httpResponse))

        let probe = makeProbe(apiKey: "bad-key", networkClient: mockNetwork)

        // When & Then
        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on HTTP 500`() async {
        // Given
        let mockNetwork = MockNetworkClient()
        let httpResponse = makeHTTPResponse(statusCode: 500)
        given(mockNetwork)
            .request(.any)
            .willReturn((Data(), httpResponse))

        let probe = makeProbe(apiKey: "test-key", networkClient: mockNetwork)

        // When & Then: must be executionFailed specifically, not any ProbeError
        do {
            _ = try await probe.probe()
            Issue.record("Expected ProbeError.executionFailed")
        } catch {
            guard case ProbeError.executionFailed = error else {
                Issue.record("Expected ProbeError.executionFailed, got \(error)")
                return
            }
        }
    }
}
