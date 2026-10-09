import Quotas
import Foundation

/// The rows a read-only query reads from the database at `path`, each column
/// as text; `name` is how the database is called in a failure. The platform's
/// SQLite answers it (the Mac's is `ReadOnlyQuery`), never writing, creating
/// or copying the database.
typealias SQLiteRows = @Sendable (_ path: String, _ query: String, _ name: String) throws -> [[String: String]]

/// `sqlite` — the first row of a read-only query against another app's own
/// database.
struct SQLiteReader: CredentialFinding {
    let file: SQLiteCredential
    let homeDirectory: URL
    let environment: @Sendable (String) -> String?
    let rows: SQLiteRows

    func find() throws -> FoundCredential? {
        let path = Paths.resolve(file.path, homeDirectory: homeDirectory, environment: environment)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let row = try rows(path, file.query, file.path.description).first else { return nil }
        let values = CredentialDocument.values(file.fields, in: row)
        guard values["token"] != nil else { return nil }
        return FoundCredential(credential: Credential(values), save: nil)
    }
}

/// `sqlite` as a fetch — the rows of a read-only query against an app's own
/// database are the answer, `[{column: text}]`. Configured while the
/// database is there.
struct SQLiteFetcher: Fetching {
    let call: SQLiteCall
    let homeDirectory: URL
    let environment: @Sendable (String) -> String?
    let rows: SQLiteRows

    private var path: String {
        Paths.resolve(call.path, homeDirectory: homeDirectory, environment: environment)
    }

    func isReady() -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func fetch(with credential: Credential?) async throws -> Response {
        let path = path
        guard FileManager.default.fileExists(atPath: path) else {
            throw UsageError.executionFailed("No database at \(call.path)")
        }
        let rows = try rows(path, call.query, call.path.description)
        return Response(body: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]))
    }
}
