import Diagnostics
import Domain
import Foundation

/// OAuth 2's refresh-token grant (RFC 6749 §6): trades `refreshToken` for a
/// new `token`, and stamps `refreshedAt`. Which provider it serves is data.
struct OAuth2Refresher: CredentialRefreshing {
    let refresh: OAuth2Refresh
    let network: any NetworkClient
    let now: @Sendable () -> Date

    var retryStatuses: [Int] { refresh.onStatus }

    func isDue(_ credential: Credential) -> Bool {
        guard let every = refresh.every else { return false }
        guard let refreshedAt = credential["refreshedAt"].flatMap(Self.parseDate) else { return true }
        return now().timeIntervalSince(refreshedAt) > every
    }

    func refresh(_ credential: Credential) async throws -> Credential {
        guard let refreshToken = credential["refreshToken"], let url = URL(string: refresh.tokenURL) else {
            throw ProbeError.authenticationRequired
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = Self.formBody([
            ("grant_type", "refresh_token"),
            ("client_id", refresh.clientId),
            ("refresh_token", refreshToken),
        ])

        let (data, response) = try await network.request(request)
        guard let http = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response from token refresh")
        }

        if http.statusCode == 400 || http.statusCode == 401 {
            let code = Self.errorCode(in: data)
            AppLog.probes.error("Token refresh refused (HTTP \(http.statusCode), \(code ?? "no code"))")
            throw ProbeError.sessionExpired(hint: refresh.hint)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProbeError.executionFailed("Token refresh failed: HTTP \(http.statusCode)")
        }

        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = body["access_token"] as? String, !token.isEmpty else {
            throw ProbeError.executionFailed("No access token in refresh response")
        }

        var renewed = credential
        renewed["token"] = token
        if let newRefreshToken = body["refresh_token"] as? String {
            renewed["refreshToken"] = newRefreshToken
        }
        if let idToken = body["id_token"] as? String {
            renewed["idToken"] = idToken
        }
        renewed["refreshedAt"] = ISO8601DateFormatter().string(from: now())
        AppLog.probes.info("Token refreshed")
        return renewed
    }

    // MARK: - Helpers

    static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        let encoded = fields.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }

    /// `{"error": {"code": …}}`, `{"error": "…"}` or `{"code": …}`.
    static func errorCode(in data: Data) -> String? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let error = body["error"] as? [String: Any], let code = error["code"] as? String { return code }
        if let error = body["error"] as? String { return error }
        return body["code"] as? String
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
