import Testing
@testable import ClaudeBar

@Suite
struct SettingsSectionSearchTests {
    @Test(arguments: ["email", "account", "label"])
    func `account label searches include menu bar settings`(query: String) {
        #expect(SettingsSection.matching(filter: query).contains(.menuBar))
    }
}
