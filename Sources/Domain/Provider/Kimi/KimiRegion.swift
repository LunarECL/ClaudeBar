import Foundation

/// The Kimi platform region to talk to.
///
/// Kimi runs two separate platforms that share the CLI and the `kimi-auth`
/// cookie name but not accounts, cookies or hosts: the China platform
/// (kimi.com) and the international platform (kimi.ai).
public enum KimiRegion: String, Sendable, Equatable, CaseIterable {
    /// China platform (kimi.com). Default for backwards compatibility:
    /// pre-region builds only supported this platform.
    case china
    /// International platform (kimi.ai).
    case international

    /// Display name for the region picker
    public var displayName: String {
        switch self {
        case .china: return "China (kimi.com)"
        case .international: return "International (kimi.ai)"
        }
    }

    /// Base URL of the web platform, used for Origin/Referer headers.
    public var webBaseURL: String {
        switch self {
        case .china: return "https://www.kimi.com"
        case .international: return "https://www.kimi.ai"
        }
    }

    /// Connect-RPC endpoint of the billing gateway used by the web console.
    public var usageURL: String {
        "\(webBaseURL)/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages"
    }

    /// Console page showing quota and plan details.
    public var consoleURL: String {
        "\(webBaseURL)/code/console"
    }

    /// Cookie domains to search for the `kimi-auth` token.
    public var cookieDomains: [String] {
        switch self {
        case .china: return ["www.kimi.com", "kimi.com"]
        case .international: return ["www.kimi.ai", "kimi.ai"]
        }
    }
}
