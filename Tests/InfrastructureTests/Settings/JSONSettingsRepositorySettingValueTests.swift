import Testing
import Foundation
@testable import Infrastructure

/// A provider-scope setting's value lives at `<id>.<setting>` — today's keys,
/// so a region chosen before the form was data is read as it was.
@Suite
struct JSONSettingsRepositorySettingValueTests {
    private func make() -> (JSONSettingsStore, JSONSettingsRepository, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let store = JSONSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        return (store, JSONSettingsRepository(store: store), directory)
    }

    @Test
    func `a value is kept under the provider and setting name`() {
        let (store, repository, directory) = make()
        defer { try? FileManager.default.removeItem(at: directory) }

        repository.setValue("international", "region", forProvider: "acme")

        #expect(repository.value("region", forProvider: "acme") == "international")
        #expect(store.read(key: "acme.region") as String? == "international")
    }

    @Test
    func `a region saved before reads as the setting's value`() {
        let (store, repository, directory) = make()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.write(value: "international", key: "kimi.region")

        #expect(repository.value("region", forProvider: "kimi") == "international")
    }

    @Test
    func `forgetting a value leaves the setting's default to apply`() {
        let (_, repository, directory) = make()
        defer { try? FileManager.default.removeItem(at: directory) }
        repository.setValue("international", "region", forProvider: "acme")

        repository.setValue(nil, "region", forProvider: "acme")

        #expect(repository.value("region", forProvider: "acme") == nil)
    }
}
