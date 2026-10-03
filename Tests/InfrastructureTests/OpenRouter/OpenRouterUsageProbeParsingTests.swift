import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct OpenRouterUsageProbeParsingTests {

    // MARK: - Sample Data

    static let sampleSuccessResponse = """
    {
      "data": {
        "total_credits": "10.00",
        "total_usage": "3.00"
      }
    }
    """

    static let sampleNumericFieldsResponse = """
    {
      "data": {
        "total_credits": 10,
        "total_usage": 2.5
      }
    }
    """

    static let sampleOverdrawnResponse = """
    {
      "data": {
        "total_credits": "10.00",
        "total_usage": "10.50"
      }
    }
    """

    static let sampleZeroUsageResponse = """
    {
      "data": {
        "total_credits": "25.00",
        "total_usage": "0.00"
      }
    }
    """

    static let sampleMissingDataResponse = """
    {
      "error": "not found"
    }
    """

    static let sampleMissingFieldsResponse = """
    {
      "data": {
        "total_credits": "10.00"
      }
    }
    """

    // MARK: - Parsing Tests

    @Test
    func `parses credits into a single credits quota`() throws {
        // Given
        let data = Data(Self.sampleSuccessResponse.utf8)

        // When
        let snapshot = try OpenRouterUsageProbe.parseResponse(data, providerId: "openrouter")

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .modelSpecific("Credits"))
        #expect(snapshot.providerId == "openrouter")
    }

    @Test
    func `maps remaining credits to dollarRemaining`() throws {
        // Given: OpenRouter reports total credits and total usage; the remaining
        // balance is credits minus usage
        let data = Data(Self.sampleSuccessResponse.utf8)

        // When
        let snapshot = try OpenRouterUsageProbe.parseResponse(data, providerId: "openrouter")

        // Then: credits are unbounded, so percent is pinned to 100
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(string: "7.00"))
        #expect(snapshot.quotas[0].percentRemaining == 100)
        #expect(snapshot.quotas[0].isDollarBased)
        // OpenRouter credits are always USD
        #expect(snapshot.quotas[0].currency == "USD")
        #expect(snapshot.quotas[0].formattedDollarRemaining == "$7.00")
    }

    @Test
    func `parses numeric total_credits and total_usage`() throws {
        // Given: the API may return numbers instead of strings
        let data = Data(Self.sampleNumericFieldsResponse.utf8)

        // When
        let snapshot = try OpenRouterUsageProbe.parseResponse(data, providerId: "openrouter")

        // Then
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(string: "7.5"))
        #expect(snapshot.quotas[0].formattedDollarRemaining == "$7.50")
    }

    @Test
    func `builds total and used breakdown resetText`() throws {
        // Given
        let data = Data(Self.sampleSuccessResponse.utf8)

        // When
        let snapshot = try OpenRouterUsageProbe.parseResponse(data, providerId: "openrouter")

        // Then
        #expect(snapshot.quotas[0].resetText == "Total: $10.00 · Used: $3.00")
    }

    @Test
    func `handles zero usage`() throws {
        // Given
        let data = Data(Self.sampleZeroUsageResponse.utf8)

        // When
        let snapshot = try OpenRouterUsageProbe.parseResponse(data, providerId: "openrouter")

        // Then
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(25))
        #expect(snapshot.quotas[0].percentRemaining == 100)
        #expect(snapshot.quotas[0].resetText == "Total: $25.00 · Used: $0.00")
    }

    @Test
    func `maps overdrawn credits to depleted status`() throws {
        // Given: usage exceeded credits
        let data = Data(Self.sampleOverdrawnResponse.utf8)

        // When
        let snapshot = try OpenRouterUsageProbe.parseResponse(data, providerId: "openrouter")

        // Then: quota is depleted but the (negative) remaining amount is still surfaced
        #expect(snapshot.quotas[0].percentRemaining == 0)
        #expect(snapshot.quotas[0].status == .depleted)
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(string: "-0.50"))
    }

    @Test
    func `throws noData when data object is missing`() throws {
        // Given
        let data = Data(Self.sampleMissingDataResponse.utf8)

        // When & Then
        #expect(throws: ProbeError.noData) {
            try OpenRouterUsageProbe.parseResponse(data, providerId: "openrouter")
        }
    }

    @Test
    func `throws parseFailed when total_usage is missing`() throws {
        // Given
        let data = Data(Self.sampleMissingFieldsResponse.utf8)

        // When & Then: must be parseFailed specifically, not any ProbeError
        do {
            _ = try OpenRouterUsageProbe.parseResponse(data, providerId: "openrouter")
            Issue.record("Expected ProbeError.parseFailed")
        } catch {
            guard case ProbeError.parseFailed = error else {
                Issue.record("Expected ProbeError.parseFailed, got \(error)")
                return
            }
        }
    }

    @Test
    func `throws parseFailed on invalid JSON`() throws {
        // Given
        let data = Data("not json".utf8)

        // When & Then: must be parseFailed specifically, not any ProbeError
        do {
            _ = try OpenRouterUsageProbe.parseResponse(data, providerId: "openrouter")
            Issue.record("Expected ProbeError.parseFailed")
        } catch {
            guard case ProbeError.parseFailed = error else {
                Issue.record("Expected ProbeError.parseFailed, got \(error)")
                return
            }
        }
    }
}
