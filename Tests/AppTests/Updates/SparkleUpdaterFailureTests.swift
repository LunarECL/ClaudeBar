import Testing
import Sparkle
@testable import ClaudeBar

/// A failed update check or install must be visible as state, not silently
/// look like "up to date" — but Sparkle's healthy outcomes must not read as
/// failures either: it reports "no update found" and the user declining an
/// install as NSError codes through the same abort callback. Sparkle's
/// installer also terminates and watches only the first running app with our
/// bundle ID, so a second ClaudeBar instance is a known risk for the install
/// handshake — the update fails on the spot yet lands on the next launch
/// when Sparkle completes the staged installation.
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
    func `no update found is a healthy outcome, not a failure`() {
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))

        #expect(!SparkleUpdater.isUpdateFailure(error))
    }

    @Test
    func `the user declining an install is not a failure`() {
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.installationCanceledError.rawValue))

        #expect(!SparkleUpdater.isUpdateFailure(error))
    }

    @Test
    func `a real Sparkle error is a failure`() {
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.installationError.rawValue))

        #expect(SparkleUpdater.isUpdateFailure(error))
    }

    @Test
    func `an error outside Sparkle's domain is a failure`() {
        let error = NSError(domain: "com.example.other", code: 42)

        #expect(SparkleUpdater.isUpdateFailure(error))
    }

    @Test
    func `only more than one running instance is a handshake risk`() {
        #expect(!SparkleUpdater.hasConflictingInstances(0))
        #expect(!SparkleUpdater.hasConflictingInstances(1))
        #expect(SparkleUpdater.hasConflictingInstances(2))
    }
}
