import Testing
import AppKit
import Domain
@testable import ClaudeBar

@Suite @MainActor
struct CodexAccountIconTests {
    @Test func `account instances keep the Codex icon`() {
        #expect(ProviderVisualIdentityLookup.iconAssetName(for: "codex.account-a") == "CodexIcon")
        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "codex.account-b") ==
                ProviderVisualIdentityLookup.symbolIcon(for: "codex"))
        #expect(ProviderVisualIdentityLookup.iconAssetName(for: "not-codex.account") != "CodexIcon")
    }

    @Test(arguments: [false, true])
    func `hiding a primary account label keeps the icon and quota layout`(stacked: Bool) throws {
        let theme = DarkTheme()
        var content = accountContent(stacked: stacked)
        let visible = StatusItemLabelDriver.compose(content, theme: theme)
        content.showAccountLabels = false
        let hidden = StatusItemLabelDriver.compose(content, theme: theme)
        content.primaryProviderName = "Codex"
        content.showAccountLabels = true
        let iconAndQuota = StatusItemLabelDriver.compose(content, theme: theme)
        #expect(hidden.size.width < visible.size.width)
        #expect(try #require(hidden.tiffRepresentation) == #require(iconAndQuota.tiffRepresentation))
        #expect(hidden.size.height == visible.size.height)
    }

    @Test(arguments: [false, true])
    func `hiding additional account labels preserves both accounts and quotas`(stacked: Bool) throws {
        let theme = DarkTheme()
        var content = accountContent(stacked: stacked)
        content.additionalLabels = [MenuBarProviderLabel(
            providerId: "codex.work", providerName: "work@example.com",
            label: content.label!, stacked: stacked
        )]
        let visible = StatusItemLabelDriver.compose(content, theme: theme)
        content.showAccountLabels = false
        let hidden = StatusItemLabelDriver.compose(content, theme: theme)
        content.primaryProviderName = "Codex"
        content.additionalLabels[0] = MenuBarProviderLabel(
            providerId: "codex.work", providerName: "Codex", label: content.label!, stacked: stacked
        )
        content.showAccountLabels = true
        let iconsAndQuotas = StatusItemLabelDriver.compose(content, theme: theme)
        #expect(hidden.size.width < visible.size.width)
        #expect(try #require(hidden.tiffRepresentation) == #require(iconsAndQuotas.tiffRepresentation))
        #expect(hidden.size.height == visible.size.height)
    }

    private func accountContent(stacked: Bool) -> StatusItemLabelDriver.LabelContent {
        StatusItemLabelDriver.LabelContent(
            label: MenuBarLabel(text: "5h 40% | 7d 60%", status: .healthy, segments: [
                .init(text: "5h 40%", status: .healthy),
                .init(text: "7d 60%", status: .healthy),
            ]),
            primaryProviderId: "codex", primaryProviderName: "personal@example.com",
            fallbackStatus: .healthy, sessionPhase: nil, themeModeId: "dark", stacked: stacked
        )
    }
}
