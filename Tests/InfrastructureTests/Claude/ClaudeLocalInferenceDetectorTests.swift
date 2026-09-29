import Foundation
import Testing
@testable import Infrastructure

@Suite
struct ClaudeLocalInferenceDetectorTests {
    private func tempConfig(_ json: String) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let url = tmpDir.appendingPathComponent(".claude.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func `missing config file is not local`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(".claude.json")
        #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url) == false)
    }

    @Test func `config without a base url is not local`() throws {
        let url = try tempConfig(#"{"oauthAccount":{"emailAddress":"a@b.c"}}"#)
        #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url) == false)
    }

    @Test func `env base url on loopback is local`() throws {
        let url = try tempConfig(#"{"env":{"ANTHROPIC_BASE_URL":"http://localhost:11434"}}"#)
        #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url))
    }

    @Test func `env base url on ipv4 loopback is local`() throws {
        let url = try tempConfig(#"{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:1234/v1"}}"#)
        #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url))
    }

    @Test func `env base url on a paid gateway is not local`() throws {
        let url = try tempConfig(#"{"env":{"ANTHROPIC_BASE_URL":"https://api.z.ai/api/anthropic"}}"#)
        #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url) == false)
    }

    @Test func `provider entry on loopback is local`() throws {
        let json = #"{"providers":[{"base_url":"https://api.anthropic.com"},{"base_url":"http://127.0.0.1:8080"}]}"#
        let url = try tempConfig(json)
        #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url))
    }

    @Test func `provider env entry on loopback is local`() throws {
        let json = #"{"providers":[{"env":{"ANTHROPIC_BASE_URL":"http://[::1]:11434"}}]}"#
        let url = try tempConfig(json)
        #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url))
    }

    @Test(arguments: [
        "http://localhost:11434",
        "http://LOCALHOST:1234",
        "https://models.localhost/v1",
        "http://0.0.0.0:8000",
    ])
    func `loopback urls are recognised`(url: String) {
        #expect(ClaudeLocalInferenceDetector.isLoopback(url))
    }

    @Test(arguments: [
        "https://api.anthropic.com",
        "https://api.z.ai/api/anthropic",
        "http://192.168.1.10:11434",
        "https://my-localhost.example.com/v1",
        "not a url",
    ])
    func `non loopback urls are not`(url: String) {
        #expect(ClaudeLocalInferenceDetector.isLoopback(url) == false)
    }
}
