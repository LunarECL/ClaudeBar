import Diagnostics
import Foundation

/// `environment` — an environment variable holds the token.
struct EnvironmentReader: CredentialFinding {
    let name: String
    let environment: @Sendable (String) -> String?

    func find() throws -> FoundCredential? {
        guard let value = environment(name), !value.isEmpty else { return nil }
        return FoundCredential(credential: Credential(["token": value]), save: nil)
    }
}

/// `jsonFile` — a JSON file holds the token and its companions. A refreshed
/// token is written back into the same file, every other field kept, because
/// the CLI that owns the file must keep working.
struct JSONFileReader: CredentialFinding {
    let file: JSONFileCredential
    let homeDirectory: URL

    var url: URL {
        if file.path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(file.path.dropFirst(2)))
        }
        return URL(fileURLWithPath: file.path)
    }

    func find() throws -> FoundCredential? {
        guard let document = readDocument() else { return nil }
        let scope = JSONScope(root: document)
        var values: [String: String] = [:]
        for (name, path) in file.fields {
            if let value = scope.string(path), !value.isEmpty {
                values[name] = value
            }
        }
        guard values["token"] != nil else { return nil }
        let reader = self
        return FoundCredential(credential: Credential(values), save: { reader.write($0) })
    }

    func write(_ credential: Credential) {
        guard var document = readDocument() else { return }
        for (name, path) in file.fields {
            if let value = credential[name] {
                document = JSONPath.set(value, at: path, in: document)
            }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            AppLog.credentials.info("Saved refreshed credentials to \(file.path)")
        } catch {
            AppLog.credentials.error("Failed to save refreshed credentials to \(file.path): \(error.localizedDescription)")
        }
    }

    private func readDocument() -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// `firstOf` — the lookup order: the first reader that answers wins.
struct FirstOfReader: CredentialFinding {
    let readers: [any CredentialFinding]

    func find() throws -> FoundCredential? {
        for reader in readers {
            if let found = try reader.find() {
                return found
            }
        }
        return nil
    }
}
