import Testing
import Foundation
@testable import ClaudeBar

@Suite
struct URLSchemeActionTests {

    @Test(arguments: [
        ("claudebar://open", URLSchemeAction.open),
        ("claudebar://refresh", .refresh),
        ("claudebar://settings", .settings),
    ])
    func `action is the URL host`(string: String, expected: URLSchemeAction) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == expected)
    }

    @Test(arguments: [
        ("claudebar:///open", URLSchemeAction.open),
        ("claudebar:///refresh", .refresh),
        ("claudebar:///settings/", .settings),
    ])
    func `action can also be given as the path`(string: String, expected: URLSchemeAction) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == expected)
    }

    @Test(arguments: ["claudebar://foo", "claudebar://", "claudebar:///"])
    func `unknown actions are nil`(string: String) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == nil)
    }

    @Test(arguments: [
        "claudebar://refresh/other?unexpected=1",
        "claudebar://open?x=1",
        "claudebar://open#top",
        "claudebar://open/extra",
        "claudebar:///open/extra",
        "claudebar:///settings?x=1",
    ])
    func `URLs with extra components are nil`(string: String) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == nil)
    }

    @Test
    func `a bare trailing slash after the host is still the action`() {
        let url = URL(string: "claudebar://open/")!
        #expect(URLSchemeAction(url: url) == .open)
    }

    @Test
    func `other schemes are nil even with a known host`() {
        let url = URL(string: "https://open")!
        #expect(URLSchemeAction(url: url) == nil)
    }
}
