import Testing
@testable import ClaudeBar

/// *Your place* under the board: a row of yours pinned below the list, so
/// you find yourself without scrolling — only while the list doesn't show
/// your own row, or you see yourself twice.
@Suite
struct PinnedPlaceTests {
    @Test func `should not pin your place when your row is in view`() {
        #expect(!PinnedPlace.shows(isRanked: true, listScrolls: true, isYourRowInView: true))
    }

    @Test func `should pin your place when your row is scrolled out of view`() {
        #expect(PinnedPlace.shows(isRanked: true, listScrolls: true, isYourRowInView: false))
    }

    @Test func `should not pin your place when the whole board fits without scrolling`() {
        #expect(!PinnedPlace.shows(isRanked: true, listScrolls: false, isYourRowInView: false))
    }

    @Test func `should not pin a place when you are not ranked`() {
        #expect(!PinnedPlace.shows(isRanked: false, listScrolls: true, isYourRowInView: false))
    }
}
