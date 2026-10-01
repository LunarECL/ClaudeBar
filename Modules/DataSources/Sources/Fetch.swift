import Foundation

/// HOW TO GET THE BYTES — *Data fetching method*. A closed sum, one case per
/// JSON tag, because the decoder must know every tag and the picker is a fixed
/// list. A new protocol is a new case and one new worker.
public enum Fetch: Sendable, Equatable {
    /// An HTTP request — the *API* choice.
    case http(HTTPRequest)
    /// A JSON-RPC conversation with a CLI over stdin/stdout.
    case jsonRpc(JSONRPCCall)
    /// A CLI run in a terminal, its screen captured — the *CLI* choice.
    case cli(CLICall)
}

/// `{{name}}` placeholders in `url`, `headers` and `body` are filled from the
/// credential at fetch time.
public struct HTTPRequest: Sendable, Equatable, Codable {
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let body: String?
    public let timeout: TimeInterval

    public init(url: String, method: String = "GET", headers: [String: String] = [:], body: String? = nil, timeout: TimeInterval = 15) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? "GET"
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        body = try container.decodeIfPresent(String.self, forKey: .body)
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 15
    }
}

/// Where a CLI runs. `probe` is ClaudeBar's own trusted directory, so a CLI's
/// folder-trust prompt never blocks a probe.
public enum WorkingDirectory: String, Sendable, Equatable, Codable {
    case probe
}

/// Starts `cli args…`, sends the `handshake` in order, then `call`, and answers
/// with the call's result.
public struct JSONRPCCall: Sendable, Equatable, Codable {
    public struct Step: Sendable, Equatable, Codable {
        /// A request, answered before the next step.
        public let request: String?
        /// A notification, never answered.
        public let notify: String?
        public let params: JSONValue?

        public init(request: String? = nil, notify: String? = nil, params: JSONValue? = nil) {
            self.request = request
            self.notify = notify
            self.params = params
        }
    }

    public let cli: String
    public let args: [String]
    public let workingDirectory: WorkingDirectory?
    public let handshake: [Step]
    public let call: String
    public let params: JSONValue?

    public init(cli: String, args: [String], workingDirectory: WorkingDirectory? = nil, handshake: [Step] = [], call: String, params: JSONValue? = nil) {
        self.cli = cli
        self.args = args
        self.workingDirectory = workingDirectory
        self.handshake = handshake
        self.call = call
        self.params = params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cli = try container.decode(String.self, forKey: .cli)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workingDirectory = try container.decodeIfPresent(WorkingDirectory.self, forKey: .workingDirectory)
        handshake = try container.decodeIfPresent([Step].self, forKey: .handshake) ?? []
        call = try container.decode(String.self, forKey: .call)
        params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
    }
}

/// Runs `cli args…` in a terminal, types `input`, answers prompts it
/// recognises from `autoResponses`, and returns what the screen showed.
public struct CLICall: Sendable, Equatable, Codable {
    public let cli: String
    public let args: [String]
    public let input: String?
    public let timeout: TimeInterval
    public let workingDirectory: WorkingDirectory?
    /// Prompt text → what to type when it appears.
    public let autoResponses: [String: String]

    public init(cli: String, args: [String] = [], input: String? = nil, timeout: TimeInterval = 20, workingDirectory: WorkingDirectory? = nil, autoResponses: [String: String] = [:]) {
        self.cli = cli
        self.args = args
        self.input = input
        self.timeout = timeout
        self.workingDirectory = workingDirectory
        self.autoResponses = autoResponses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cli = try container.decode(String.self, forKey: .cli)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        input = try container.decodeIfPresent(String.self, forKey: .input)
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 20
        workingDirectory = try container.decodeIfPresent(WorkingDirectory.self, forKey: .workingDirectory)
        autoResponses = try container.decodeIfPresent([String: String].self, forKey: .autoResponses) ?? [:]
    }
}

// MARK: - JSON

extension Fetch: Codable {
    private static let tags = ["http", "jsonRpc", "cli"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        switch try container.singleTag(of: Self.tags, in: "fetch") {
        case "http": self = .http(try container.decode(HTTPRequest.self, forKey: TagKey("http")))
        case "jsonRpc": self = .jsonRpc(try container.decode(JSONRPCCall.self, forKey: TagKey("jsonRpc")))
        default: self = .cli(try container.decode(CLICall.self, forKey: TagKey("cli")))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .http(let request): try container.encode(request, forKey: TagKey("http"))
        case .jsonRpc(let call): try container.encode(call, forKey: TagKey("jsonRpc"))
        case .cli(let call): try container.encode(call, forKey: TagKey("cli"))
        }
    }
}
