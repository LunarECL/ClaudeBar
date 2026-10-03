import Diagnostics
import Quotas
import Foundation

/// `http.steps` — the requests in order, each filled with the credential and
/// the values earlier steps kept. A kept value never replaces a credential
/// value. The last step that ran is the response.
struct HTTPStepsFetcher: Fetching {
    let steps: HTTPSteps
    let network: any NetworkClient
    let now: @Sendable () -> Date

    func isReady() -> Bool { true }

    func fetch(with credential: Credential?) async throws -> Response {
        var values = credential ?? Credential([:])
        var last: Response?
        for step in steps.steps {
            if let known = step.unless, values[known] != nil {
                AppLog.probes.debug("http step \(step.name): skipped, \(known) is known")
                continue
            }
            do {
                let response = try await send(step, with: values)
                for (name, value) in Self.kept(step.keep, from: response) where values[name] == nil {
                    values[name] = value
                }
                last = response
            } catch {
                guard step.optional else { throw error }
                AppLog.probes.info("http step \(step.name): failed, going on without it")
            }
        }
        guard let last else { throw UsageError.noData }
        return last
    }

    /// One step, tried again on a network failure or a 5xx.
    private func send(_ step: HTTPStep, with values: Credential) async throws -> Response {
        var filled = values
        for name in step.dropEmpty where filled[name] == nil { filled[name] = "" }
        let request = Self.droppingEmpty(step.dropEmpty, from: step.request, values: filled)
        let fetcher = HTTPFetcher(request: request, network: network, now: now)
        var attempt = 1
        while true {
            do {
                return try await fetcher.fetch(with: filled)
            } catch let error as HTTPStatusError where (500..<600).contains(error.status) && attempt < step.attempts {
                attempt += 1
            } catch let error as UsageError where error.tag == "executionFailed" && attempt < step.attempts {
                attempt += 1
            }
        }
    }

    /// The request with each JSON body key in `names` removed when its value
    /// is empty — `{"project": "{{project}}"}` becomes `{}` without a project.
    static func droppingEmpty(_ names: [String], from request: HTTPRequest, values: Credential) -> HTTPRequest {
        guard !names.isEmpty, let body = request.body,
              let filled = Template.fill(body, with: values),
              var object = (try? JSONSerialization.jsonObject(with: Data(filled.utf8))) as? [String: Any] else {
            return request
        }
        for name in names where (object[name] as? String)?.isEmpty == true {
            object.removeValue(forKey: name)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return request }
        return HTTPRequest(url: request.url, method: request.method, headers: request.headers,
                           body: String(decoding: data, as: UTF8.self), timeout: request.timeout,
                           acceptedStatuses: request.acceptedStatuses)
    }

    /// The values a step keeps from its response; one that is absent is left out.
    static func kept(_ keep: [String: HTTPStep.Keep], from response: Response) -> [String: String] {
        let json = try? JSONSerialization.jsonObject(with: response.body, options: [.fragmentsAllowed])
        var values: [String: String] = [:]
        for (name, rule) in keep {
            switch rule {
            case .path(let path):
                if let value = JSONPath.string(JSONPath.walk(json, JSONPath.components(path))), !value.isEmpty {
                    values[name] = value
                }
            case .pattern(let pattern):
                let text = response.text
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
                    values[name] = String(text[range])
                }
            }
        }
        return values
    }
}
