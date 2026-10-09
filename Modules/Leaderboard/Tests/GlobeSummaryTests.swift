import Testing
@testable import Leaderboard

@Suite
struct GlobeSummaryTests {
    @Test func `should count every country on the globe, with numbers or without`() {
        let globe = GlobeSummary(countries: [.init(country: "NL", members: 3, tokens: 300)], present: ["GR", "VN"])

        #expect(globe.countryCount == 3)
    }

    @Test func `should count no countries when no one shares theirs`() {
        #expect(GlobeSummary(countries: [], present: []).countryCount == 0)
    }
}
