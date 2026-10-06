import SwiftUI
import Testing
import Domain
@testable import ClaudeBar

/// Platformer: a Super Mario–style 8-bit theme. Blue sky, ink outlines with
/// hard shadows, quota bars as a row of ten blocks, big numbers in a pixel
/// font, and a low or empty quota that says HURRY UP! or GAME OVER.
/// Every other theme keeps its bar, its plain words and its own tagline.
@MainActor
@Suite
struct PlatformerThemeTests {
    @Test func `should offer Platformer among the built-in themes`() {
        #expect(ThemeRegistry.shared.theme(for: "platformer")?.displayName == "Platformer")
        #expect(ThemeMode(rawValue: "platformer") == .platformer)
    }

    @Test func `should outline Platformer's cards in ink with a hard shadow`() {
        let theme = PlatformerTheme()
        #expect(theme.glassBorder == PlatformerTheme.ink)
        #expect(theme.cardShadow == ThemeShadow(color: PlatformerTheme.ink, radius: 0, x: 4, y: 4))
        // Outlined: big numbers print outlined, Settings draws paper.
        #expect(theme.isOutlined)
    }

    @Test func `should draw Platformer's quota bars as a row of ten blocks`() {
        #expect(PlatformerTheme().progressStyle == .blocks(10))
    }

    @Test func `should show Platformer's big numbers in a pixel font`() {
        #expect(PlatformerTheme().displayFontName == "PressStart2P-Regular")
        // Wide pixels print smaller, so "$125.00" fits its card.
        #expect(PlatformerTheme().displayFontScale < 1)
    }

    @Test func `should write every word in a pixel face, with square badges`() {
        let theme = PlatformerTheme()
        #expect(theme.customFontName == "PixelifySans")
        #expect(theme.pillCornerRadius == 3)
    }

    @Test func `should say HURRY UP when a quota runs low and GAME OVER when it is empty`() {
        let theme = PlatformerTheme()
        #expect(theme.statusWord(for: .healthy) == "HEALTHY")
        #expect(theme.statusWord(for: .warning) == "WARNING")
        #expect(theme.statusWord(for: .critical) == "HURRY UP!")
        #expect(theme.statusWord(for: .depleted) == "GAME OVER")
    }

    @Test func `should keep Platformer's blocks and words when the person picks their own status colours`() throws {
        let theme = ThemeRegistry.shared.resolveTheme(
            for: "platformer",
            systemColorScheme: .light,
            statusColors: StatusColorPolicy(overrides: StatusColorOverrides(healthy: RGBColorValue(red: 0, green: 0, blue: 1)), highContrastEnabled: false)
        )
        #expect(theme.progressStyle == .blocks(10))
        #expect(theme.statusWord(for: .depleted) == "GAME OVER")
        #expect(theme.tagline == PlatformerTheme().tagline)
    }

    @Test(arguments: ["light", "dark", "system", "cli", "christmas", "pop"])
    func `should keep every other theme's bar and plain status words`(id: String) throws {
        let theme = try #require(ThemeRegistry.shared.theme(for: id))
        #expect(theme.progressStyle == .bar)
        #expect(theme.displayFontScale == 1)
        #expect(theme.customFontName == nil)
        #expect(theme.statusWord(for: .critical) == "LOW")
        #expect(theme.statusWord(for: .depleted) == "EMPTY")
    }

    @Test func `should give each theme its own line under ClaudeBar's name`() throws {
        #expect(try #require(ThemeRegistry.shared.theme(for: "light")).tagline == nil)
        #expect(try #require(ThemeRegistry.shared.theme(for: "cli")).tagline == "> usage monitor")
        #expect(try #require(ThemeRegistry.shared.theme(for: "christmas")).tagline == "Happy Holidays!")
        #expect(try #require(ThemeRegistry.shared.theme(for: "pop")).tagline == "Your quotas, the cute way")
        #expect(PlatformerTheme().tagline == "Your quotas, one level at a time")
    }
}

/// A quota bar drawn as blocks: one block per tenth, rounded to the
/// nearest, and never empty while anything is left.
@Suite
struct ProgressBlocksTests {
    @Test func `should fill blocks to the nearest tenth`() {
        #expect(ProgressBlocks.filled(percent: 62, of: 10) == 6)
        #expect(ProgressBlocks.filled(percent: 66, of: 10) == 7)
        #expect(ProgressBlocks.filled(percent: 100, of: 10) == 10)
    }

    @Test func `should keep one block lit while a quota has anything left`() {
        #expect(ProgressBlocks.filled(percent: 2, of: 10) == 1)
    }

    @Test func `should light no block when a quota is empty`() {
        #expect(ProgressBlocks.filled(percent: 0, of: 10) == 0)
        #expect(ProgressBlocks.filled(percent: -5, of: 10) == 0)
    }

    @Test func `should never light more blocks than the bar has`() {
        #expect(ProgressBlocks.filled(percent: 140, of: 10) == 10)
    }
}
