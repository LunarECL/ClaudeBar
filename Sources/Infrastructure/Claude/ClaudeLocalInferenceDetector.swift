import Foundation

/// Detects whether Claude Code is routed at a **local** inference endpoint.
///
/// Claude Code lets you point `ANTHROPIC_BASE_URL` at anything: a paid gateway
/// (z.ai, Bedrock, a corporate proxy) or a server on this machine (ollama,
/// LM Studio, llama.cpp). Only the second kind cannot cost money per token, so
/// this is the fact the cost estimator needs and the model name cannot supply —
/// a local server may serve a model we have never heard of, under any name.
///
/// Read from `~/.claude.json`, the same file `ZaiUsageProbe` inspects:
/// `env.ANTHROPIC_BASE_URL` (Claude Code's own setting) and the `providers`
/// array form. A missing, unreadable or remote URL simply means "not local".
public enum ClaudeLocalInferenceDetector {
    /// Hosts that address this machine.
    private static let loopbackHosts: Set<String> = [
        "localhost", "127.0.0.1", "::1", "0.0.0.0",
    ]

    /// Whether `~/.claude.json` routes requests to a loopback endpoint.
    /// Re-reads on every call so a machine switched to a local server is picked
    /// up by the next scan without an app restart.
    public static func isLocallyServed(configURL: URL? = nil) -> Bool {
        let url = configURL ?? defaultConfigURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        return baseURLs(in: root).contains(where: isLoopback)
    }

    /// Whether a base URL string points at this machine.
    /// A host we cannot parse is treated as remote: charging nothing because a
    /// URL failed to parse would silently under-report real spend.
    static func isLoopback(_ baseURL: String) -> Bool {
        guard let host = URLComponents(string: baseURL)?.host?.lowercased() else { return false }
        // URLComponents keeps the brackets of an IPv6 literal ("[::1]").
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return loopbackHosts.contains(bare) || bare.hasSuffix(".localhost")
    }

    /// Every `ANTHROPIC_BASE_URL` Claude Code could be using.
    static func baseURLs(in root: [String: Any]) -> [String] {
        var urls: [String] = []
        if let env = root["env"] as? [String: Any],
           let baseURL = env["ANTHROPIC_BASE_URL"] as? String {
            urls.append(baseURL)
        }
        for provider in root["providers"] as? [[String: Any]] ?? [] {
            if let baseURL = provider["base_url"] as? String { urls.append(baseURL) }
            if let env = provider["env"] as? [String: Any],
               let baseURL = env["ANTHROPIC_BASE_URL"] as? String {
                urls.append(baseURL)
            }
        }
        return urls
    }

    /// Mirrors `CLAUDE_CONFIG_DIR` handling in `ClaudeAccountInfoResolver`.
    private static func defaultConfigURL() -> URL {
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        return (configDir ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent(".claude.json")
    }
}
