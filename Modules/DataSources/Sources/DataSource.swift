import Diagnostics
import Domain
import Foundation

/// ONE type that fetches for every provider: its definition, made live by
/// `DataSources.make` with only the connection its fetch needs.
///
/// `fetchUsage()` is *Fetching usage data…*: look up the key, fetch, map.
/// `fetchResponse()` is *Test Connection*: it stops before mapping, so a person
/// with nothing mapped yet can see what came back.
public struct DataSource: Sendable {
    public let definition: DataSourceDefinition
    public let providerId: String

    private let credentials: (any CredentialFinding)?
    private let refresher: (any CredentialRefreshing)?
    private let fetcher: any Fetching
    private let mapper: any Reading

    init(
        definition: DataSourceDefinition,
        providerId: String,
        credentials: (any CredentialFinding)?,
        refresher: (any CredentialRefreshing)?,
        fetcher: any Fetching,
        mapper: any Reading
    ) {
        self.definition = definition
        self.providerId = providerId
        self.credentials = credentials
        self.refresher = refresher
        self.fetcher = fetcher
        self.mapper = mapper
    }

    public var kind: String { definition.kind }

    /// Whether the key lookup finds a key — *OAuth credentials found*.
    /// `true` for a data source that needs none.
    public var hasKey: Bool {
        guard let credentials else { return true }
        return (try? credentials.find()) != nil
    }

    /// *Configured*: the key answers (when one is needed) and the CLI exists.
    public func isReady() async -> Bool {
        if let credentials, (try? credentials.find()) == nil {
            return false
        }
        return fetcher.isReady()
    }

    /// Looks up the key and fetches. Nothing is mapped and nothing is saved.
    /// Throws a `DataSourceError` naming the step that failed.
    public func fetchResponse() async throws -> Response {
        var found = try lookUp()

        if let refresher, let current = found, refresher.isDue(current.credential) {
            do {
                found = try await refreshed(current, by: refresher)
            } catch let error as DataSourceError where error.reason.isSessionExpired {
                throw error
            } catch {
                // A proactive refresh that fails is not fatal: the token we
                // have may still work. Only "log in again" stops the fetch.
                AppLog.probes.warning("\(providerId) \(kind): refresh failed, trying the current token")
            }
        }

        do {
            return try await fetcher.fetch(with: found?.credential)
        } catch let refused as HTTPStatusError {
            guard let refresher, let current = found, refresher.retryStatuses.contains(refused.status) else {
                throw DataSourceError(.fetch, refused.reason)
            }
            AppLog.probes.info("\(providerId) \(kind): HTTP \(refused.status), refreshing the token once")
            let renewed = try await refreshed(current, by: refresher)
            do {
                return try await fetcher.fetch(with: renewed.credential)
            } catch {
                throw Self.fetchError(error)
            }
        } catch {
            throw Self.fetchError(error)
        }
    }

    /// *Fetching usage data…* — `mapping.read(fetchResponse())`.
    /// Throws a `DataSourceError` naming the step that failed.
    public func fetchUsage() async throws -> UsageSnapshot {
        let response = try await fetchResponse()
        return try read(response)
    }

    /// *Map fields*' live card: reads a response already fetched.
    public func read(_ response: Response) throws -> UsageSnapshot {
        do {
            return try mapper.read(response, providerId: providerId)
        } catch {
            throw DataSourceError.wrap(error, as: .mapping)
        }
    }

    // MARK: - Private

    private func lookUp() throws -> FoundCredential? {
        guard let credentials else { return nil }
        let found: FoundCredential?
        do {
            found = try credentials.find()
        } catch {
            throw DataSourceError.wrap(error, as: .lookup)
        }
        guard let found else {
            throw DataSourceError(.lookup, .authenticationRequired)
        }
        return found
    }

    /// Refreshes the token and writes it back where it was found.
    private func refreshed(_ found: FoundCredential, by refresher: any CredentialRefreshing) async throws -> FoundCredential {
        var renewed = found
        do {
            renewed.credential = try await refresher.refresh(found.credential)
        } catch {
            throw DataSourceError.wrap(error, as: .lookup)
        }
        renewed.save?(renewed.credential)
        return renewed
    }

    private static func fetchError(_ error: Error) -> DataSourceError {
        if let refused = error as? HTTPStatusError {
            return DataSourceError(.fetch, refused.reason)
        }
        return DataSourceError.wrap(error, as: .fetch)
    }
}

extension ProbeError {
    var isSessionExpired: Bool {
        if case .sessionExpired = self { return true }
        return false
    }
}

// MARK: - The workers' roles (internal: the factory picks them)

/// A credential found, and how to write a refreshed one back where it came from.
struct FoundCredential: Sendable {
    var credential: Credential
    let save: (@Sendable (Credential) -> Void)?
}

protocol CredentialFinding: Sendable {
    /// `nil` when nothing answered — *Key needed*.
    func find() throws -> FoundCredential?
}

protocol CredentialRefreshing: Sendable {
    var retryStatuses: [Int] { get }
    func isDue(_ credential: Credential) -> Bool
    func refresh(_ credential: Credential) async throws -> Credential
}

protocol Fetching: Sendable {
    func isReady() -> Bool
    func fetch(with credential: Credential?) async throws -> Response
}

protocol Reading: Sendable {
    func read(_ response: Response, providerId: String) throws -> UsageSnapshot
}

/// An HTTP answer outside 2xx, kept with its status so a refresh can be tried.
struct HTTPStatusError: Error, Sendable {
    let status: Int
    let reason: ProbeError
}
