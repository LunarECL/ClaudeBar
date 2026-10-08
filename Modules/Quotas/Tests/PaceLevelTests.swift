import Testing
import Foundation
@testable import Quotas

@Suite
struct PaceLevelTests {

    @Test
    func `should grade the projected end-of-window usage into six levels`() {
        // projected = used / elapsed
        #expect(PaceLevel.from(percentUsed: 20, percentTimeElapsed: 50) == .comfortable) // 40%
        #expect(PaceLevel.from(percentUsed: 30, percentTimeElapsed: 50) == .onTrack)     // 60%
        #expect(PaceLevel.from(percentUsed: 40, percentTimeElapsed: 50) == .warming)     // 80%
        #expect(PaceLevel.from(percentUsed: 47, percentTimeElapsed: 50) == .pressing)    // 94%
        #expect(PaceLevel.from(percentUsed: 55, percentTimeElapsed: 50) == .critical)    // 110%
        #expect(PaceLevel.from(percentUsed: 70, percentTimeElapsed: 50) == .runaway)     // 140%
    }

    @Test
    func `should put each boundary in the higher level`() {
        #expect(PaceLevel.from(percentUsed: 25, percentTimeElapsed: 50) == .onTrack)   // 50%
        #expect(PaceLevel.from(percentUsed: 45, percentTimeElapsed: 50) == .pressing)  // 90%
        #expect(PaceLevel.from(percentUsed: 50, percentTimeElapsed: 50) == .critical)  // 100%
        #expect(PaceLevel.from(percentUsed: 60, percentTimeElapsed: 50) == .runaway)   // 120%
    }

    @Test
    func `should call an unused quota comfortable`() {
        #expect(PaceLevel.from(percentUsed: 0, percentTimeElapsed: 50) == .comfortable)
    }

    @Test
    func `should have no level before 3 percent of the window or once it is over`() {
        #expect(PaceLevel.from(percentUsed: 10, percentTimeElapsed: 2.9) == nil)
        #expect(PaceLevel.from(percentUsed: 10, percentTimeElapsed: 100) == nil)
        #expect(PaceLevel.from(percentUsed: 1, percentTimeElapsed: 3) == .comfortable) // 33%
    }
}
