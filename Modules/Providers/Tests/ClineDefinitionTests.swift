import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// Cline as data: the plan's five-hour, weekly and monthly limits from
/// `api.cline.bot`, with a pasted key or the login `cline auth` saved.
@MainActor @Suite
struct ClineDefinitionTests {
    static let limits = #"""
    {"success":true,"data":{"limits":[
     {"type":"five_hour","percentUsed":12.5,"resetsAt":"2026-07-16T15:00:00Z"},
     {"type":"experimental_pool","percentUsed":77,"resetsAt":"2026-07-16T15:00:00Z"},
     {"type":"weekly","percentUsed":25,"resetsAt":"2026-07-20T00:00:00Z"},
     {"type":"monthly","percentUsed":40,"resetsAt":null}]}}
    """#

    /// The Authorization header of the last request, kept across the mock's thread.
    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?

        func record(_ header: String?) {
            lock.lock(); defer { lock.unlock() }
            value = header
        }

        var last: String? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    /// A Cline login file under a fresh home folder, written as `cline auth` saves it.
    private func home(settings: [String: Any]? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent(".cline/data/settings")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let settings {
            let file = ["providers": ["cline": ["settings": settings]]]
            try JSONSerialization.data(withJSONObject: file).write(to: folder.appendingPathComponent("providers.json"))
        }
        return root
    }

    private func make(body: String = Self.limits, status: Int = 200, home: URL? = nil, environment: [String: String] = [:],
                      vault: MemoryVault = MemoryVault(), seen: Seen = Seen()) throws -> Provider {
        let definition = try ProviderFactory.builtIn("cline")
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            guard request.url?.absoluteString == "https://api.cline.bot/api/v1/users/me/plan/usage-limits",
                  request.httpMethod == "GET",
                  request.value(forHTTPHeaderField: "Accept") == "application/json" else {
                return (Data(), StubbedProvider.response(400))
            }
            seen.record(request.value(forHTTPHeaderField: "Authorization"))
            return (Data(body.utf8), StubbedProvider.response(status))
        }
        let folder = try home ?? self.home()
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { environment[$0] },
                             homeDirectory: folder, now: { Date() })
        }, vault: vault)
    }

    @Test
    func `should be Cline, off until turned on, with its dashboard and icon`() throws {
        let cline = try make()
        #expect(cline.id == "cline")
        #expect(cline.name == "Cline")
        #expect(cline.plainIsInLineup == false)
        #expect(cline.definition.profile.links.dashboard == URL(string: "https://app.cline.bot/dashboard"))
        #expect(cline.definition.profile.look.icon == "ClineIcon")
    }

    @Test
    func `should show the five-hour, weekly and monthly limits and skip a limit it doesn't know`() async throws {
        let usage = try await make(environment: ["CLINE_API_KEY": "key"]).refreshPlain()

        #expect(usage.quotas.count == 3)
        let session = try #require(usage.quota(for: .session))
        #expect(session.percentRemaining == 87.5)
        #expect(session.resetsAt == ISO8601DateFormatter().date(from: "2026-07-16T15:00:00Z"))
        #expect(usage.quota(for: .weekly)?.percentRemaining == 75)
        #expect(usage.quota(for: .weekly)?.resetsAt == ISO8601DateFormatter().date(from: "2026-07-20T00:00:00Z"))
        let monthly = try #require(usage.quotas.first { $0.quotaType == .timeLimit("Monthly") })
        #expect(monthly.percentRemaining == 60)
        #expect(monthly.resetsAt == nil)
    }

    @Test
    func `should send a pasted key as it is`() async throws {
        let seen = Seen()
        _ = try await make(vault: MemoryVault(["cline.apiKey": "pasted"]), seen: seen).refreshPlain()
        #expect(seen.last == "Bearer pasted")
    }

    @Test
    func `should use the login cline auth saved, marked as a WorkOS token`() async throws {
        let seen = Seen()
        let home = try home(settings: ["auth": ["accessToken": "session-token"]])
        _ = try await make(home: home, seen: seen).refreshPlain()
        #expect(seen.last == "Bearer workos:session-token")
    }

    @Test
    func `should not mark a saved login twice when it is already a WorkOS token`() async throws {
        let seen = Seen()
        let home = try home(settings: ["auth": ["accessToken": "workos:session-token"]])
        _ = try await make(home: home, seen: seen).refreshPlain()
        #expect(seen.last == "Bearer workos:session-token")
    }

    @Test
    func `should use the API key saved in Cline's settings when it has no login`() async throws {
        let seen = Seen()
        let home = try home(settings: ["apiKey": "settings-key"])
        _ = try await make(home: home, seen: seen).refreshPlain()
        #expect(seen.last == "Bearer settings-key")
    }

    @Test
    func `should prefer the environment key over Cline's own login`() async throws {
        let seen = Seen()
        let home = try home(settings: ["auth": ["accessToken": "session-token"]])
        _ = try await make(home: home, environment: ["CLINE_API_KEY": "environment"], seen: seen).refreshPlain()
        #expect(seen.last == "Bearer environment")
    }

    @Test
    func `should ask for a key when there is neither a key nor a Cline login`() async throws {
        let cline = try make()
        let account = cline.defaultAccount
        await #expect(throws: UsageError.authenticationRequired) { try await cline.refresh(account) }
        #expect(account.lastFailedStep == .lookup)
    }

    @Test(arguments: [401, 403])
    func `should ask to sign in again when Cline refuses the key`(_ status: Int) async throws {
        let cline = try make(status: status, environment: ["CLINE_API_KEY": "key"])
        await #expect(throws: UsageError.sessionExpired(hint: "Run `cline auth` or paste a new API key.")) {
            try await cline.refresh(cline.defaultAccount)
        }
    }

    @Test(arguments: [#"{"success":false}"#, #"{"success":true,"data":{"limits":[]}}"#])
    func `should fail reading the limits when Cline lists none`(_ body: String) async throws {
        let cline = try make(body: body, environment: ["CLINE_API_KEY": "key"])
        let account = cline.defaultAccount
        await #expect(throws: UsageError.self) { try await cline.refresh(account) }
        #expect(account.lastFailedStep == .mapping)
    }
}
