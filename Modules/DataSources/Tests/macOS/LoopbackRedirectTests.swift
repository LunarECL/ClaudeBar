#if os(macOS)
import Foundation
import Testing
@testable import DataSources

@Suite struct LoopbackRedirectTests {
    @Test func `should reject a remote request before opening a connection`() async {
        await #expect(throws: URLError.self) {
            try await InsecureLocalhostNetworkClient().request(URLRequest(url: URL(string: "https://example.invalid/usage")!))
        }
    }
    @Test func `should follow redirects within the same local server`() {
        let delegate: any URLSessionTaskDelegate = InsecureLocalhostDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://127.0.0.1:5001/usage")!
        let destination = URL(string: "https://127.0.0.1:5001/status")!
        let task = session.dataTask(with: original)
        var redirected: URLRequest?
        delegate.urlSession?(session, task: task,
            willPerformHTTPRedirection: HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil)!,
            newRequest: URLRequest(url: destination)) { redirected = $0 }
        #expect(redirected?.url == destination)
    }

    @Test(arguments: ["https://example.com/status", "https://127.0.0.1:8888/status"])
    func `should refuse local server redirects to another origin`(_ destination: String) throws {
        let delegate: any URLSessionTaskDelegate = InsecureLocalhostDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://127.0.0.1:5001/usage")!
        let task = session.dataTask(with: original)
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var handled = false
        var redirected: URLRequest?
        delegate.urlSession?(session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: destination)!)) { request in
                handled = true
                redirected = request
            }
        #expect(handled)
        #expect(redirected == nil)
    }
}
#endif
