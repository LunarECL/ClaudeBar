import Foundation
import Testing
@testable import ClaudeBar

/// Sparkle reports a healthy "no update found" (`SUNoUpdateError`) and the
/// user declining an install (`SUInstallationCanceledError`) as NSError codes
/// through the same abort callback that carries real failures, so the
/// updater's failure logging must not count them. The codes below are
/// `SUError`'s raw values (SUErrors.h), kept literal so the test target does
/// not need a Sparkle dependency. Tests never construct `SparkleUpdater`:
/// in the test host it would start a live updater against the real appcast.
@MainActor
@Suite
struct SparkleUpdaterFailureTests {

    @Test
    func `should treat no update found as a healthy outcome, not a failure`() {
        let error = NSError(domain: "SUSparkleErrorDomain", code: 1001)

        #expect(!SparkleUpdater.isUpdateFailure(error))
    }

    @Test
    func `should treat the user declining an install as a healthy outcome, not a failure`() {
        let error = NSError(domain: "SUSparkleErrorDomain", code: 4007)

        #expect(!SparkleUpdater.isUpdateFailure(error))
    }

    @Test
    func `should treat a real Sparkle error as a failure`() {
        let error = NSError(domain: "SUSparkleErrorDomain", code: 4005)

        #expect(SparkleUpdater.isUpdateFailure(error))
    }

    @Test
    func `should treat an error outside Sparkle's domain as a failure`() {
        let error = NSError(domain: "com.example.other", code: 42)

        #expect(SparkleUpdater.isUpdateFailure(error))
    }
}
