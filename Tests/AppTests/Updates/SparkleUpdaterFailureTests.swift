import Testing
@testable import ClaudeBar

/// A failed update check or install must be visible as state, not silently
/// look like "up to date". Sparkle's installer also terminates and watches
/// only the first running app with our bundle ID, so a second ClaudeBar
/// instance is a known risk for the install handshake — the update fails on
/// the spot yet lands on the next launch when Sparkle completes the staged
/// installation. These tests pin the state that makes both visible.
@MainActor
@Suite
struct SparkleUpdaterFailureTests {

    @Test
    func `a failed check or install is recorded as the last failure`() {
        let updater = SparkleUpdater()

        updater.recordFailure("The installation failed: handshake timeout")

        #expect(updater.lastFailureMessage == "The installation failed: handshake timeout")
    }

    @Test
    func `a later failure replaces an earlier one`() {
        let updater = SparkleUpdater()

        updater.recordFailure("first failure")
        updater.recordFailure("second failure")

        #expect(updater.lastFailureMessage == "second failure")
    }

    @Test
    func `finding a valid update clears the failure`() {
        let updater = SparkleUpdater()
        updater.recordFailure("download failed")

        updater.setUpdateAvailable(version: "0.6.0")

        #expect(updater.lastFailureMessage == nil)
        #expect(updater.isUpdateAvailable)
    }

    @Test
    func `a clean no-update check clears the failure`() {
        let updater = SparkleUpdater()
        updater.recordFailure("appcast unreachable")

        updater.clearUpdateAvailable()

        #expect(updater.lastFailureMessage == nil)
        #expect(!updater.isUpdateAvailable)
    }

    @Test
    func `only more than one running instance is a handshake risk`() {
        #expect(!SparkleUpdater.hasConflictingInstances(0))
        #expect(!SparkleUpdater.hasConflictingInstances(1))
        #expect(SparkleUpdater.hasConflictingInstances(2))
    }
}
