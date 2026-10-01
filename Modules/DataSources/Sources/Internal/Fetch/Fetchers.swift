import Diagnostics
import Domain
import Foundation

/// Fills `{{name}}` from a credential. `nil` when a placeholder has no value,
/// so a header like `ChatGPT-Account-Id: {{account}}` is simply left out.
enum Template {
    static func fill(_ text: String, with credential: Credential?) -> String? {
        var result = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{") {
            result += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "}}") else { return nil }
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            guard let value = credential?[name] else { return nil }
            result += value
            rest = rest[close.upperBound...]
        }
        return result + rest
    }
}

/// `http` — one HTTP request. 2xx answers with the response; anything else
/// becomes the `ProbeError` today's probes report, keeping its status so a
/// refresh-and-retry can be tried.
struct HTTPFetcher: Fetching {
    let request: HTTPRequest
    let network: any NetworkClient
    let now: @Sendable () -> Date

    static let defaultRetryAfter: TimeInterval = 5 * 60

    func isReady() -> Bool { true }

    func fetch(with credential: Credential?) async throws -> Response {
        guard let urlText = Template.fill(request.url, with: credential), let url = URL(string: urlText) else {
            throw ProbeError.executionFailed("Invalid URL")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeout
        for (name, value) in request.headers {
            if let filled = Template.fill(value, with: credential) {
                urlRequest.setValue(filled, forHTTPHeaderField: name)
            }
        }
        if let body = request.body, let filled = Template.fill(body, with: credential) {
            urlRequest.httpBody = Data(filled.utf8)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await network.request(urlRequest)
        } catch {
            AppLog.probes.error("HTTP fetch failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Network error: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String {
                headers[name] = value
            }
        }

        switch http.statusCode {
        case 200..<300:
            return Response(status: http.statusCode, headers: headers, body: data)
        case 401, 403:
            throw HTTPStatusError(status: http.statusCode, reason: .authenticationRequired)
        case 429:
            let wait = Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: now()) ?? Self.defaultRetryAfter
            throw HTTPStatusError(status: 429, reason: .rateLimited(retryAt: now().addingTimeInterval(wait)))
        default:
            AppLog.probes.error("HTTP fetch: status \(http.statusCode)")
            throw HTTPStatusError(status: http.statusCode, reason: .executionFailed("HTTP error: \(http.statusCode)"))
        }
    }

    /// `Retry-After` as seconds, or as an HTTP date.
    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
}

/// `jsonRpc` — starts the CLI, sends the handshake, then the call, and
/// answers with the call's whole message as the response body.
struct JSONRPCFetcher: Fetching {
    let call: JSONRPCCall
    let cliExecutor: any CLIExecutor
    let makeTransport: DataSources.TransportFactory

    func isReady() -> Bool {
        if cliExecutor.locate(call.cli) != nil { return true }
        AppLog.probes.error("'\(call.cli)' not found in PATH")
        return false
    }

    func fetch(with credential: Credential?) async throws -> Response {
        let directory = call.workingDirectory == .probe ? ProbeWorkingDirectory.resolve() : nil
        let transport = try makeTransport(call.cli, call.args, directory)
        defer { transport.close() }

        let session = RPCSession(transport: transport)
        for step in call.handshake {
            if let method = step.request {
                _ = try await session.request(method, params: step.params)
            } else if let method = step.notify {
                try session.notify(method, params: step.params)
            }
        }
        let message = try await session.request(call.call, params: call.params)
        AppLog.probes.debug("\(call.cli) \(call.call) answered")
        return Response(body: try JSONSerialization.data(withJSONObject: message))
    }
}

/// Newline-delimited JSON-RPC over a transport: numbered requests, answers
/// matched by id, notifications skipped.
final class RPCSession: @unchecked Sendable {
    private let transport: any RPCTransport
    private var nextID = 1

    init(transport: any RPCTransport) {
        self.transport = transport
    }

    func request(_ method: String, params: JSONValue?) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try send(["id": id, "method": method, "params": params?.foundationObject ?? [String: Any]()])
        while true {
            let data = try await transport.receive()
            guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let messageID = message["id"] as? Int, messageID == id else {
                continue
            }
            if let error = message["error"] as? [String: Any], let text = error["message"] as? String {
                throw ProbeError.executionFailed("RPC error: \(text)")
            }
            return message
        }
    }

    func notify(_ method: String, params: JSONValue?) throws {
        try send(["method": method, "params": params?.foundationObject ?? [String: Any]()])
    }

    private func send(_ payload: [String: Any]) throws {
        try transport.send(try JSONSerialization.data(withJSONObject: payload))
    }
}

/// `cli` — runs the CLI in a terminal and answers with what the screen showed.
struct CLIFetcher: Fetching {
    let call: CLICall
    let cliExecutor: any CLIExecutor

    func isReady() -> Bool {
        cliExecutor.locate(call.cli) != nil
    }

    func fetch(with credential: Credential?) async throws -> Response {
        let directory = call.workingDirectory == .probe ? ProbeWorkingDirectory.resolve() : nil
        let result = try await cliExecutor.execute(
            binary: call.cli,
            args: call.args,
            input: call.input,
            timeout: call.timeout,
            workingDirectory: directory,
            autoResponses: call.autoResponses
        )
        AppLog.probes.debug("\(call.cli) screen captured (\(result.output.count) chars)")
        return Response(text: result.output)
    }
}
