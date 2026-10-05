import Foundation

/// A login as a child process. Its output is never read or logged: a login's
/// diagnostics can carry a token.
public struct FoundationSignInProcess: SignInProcess {
    public init() {}

    public func run(executable: String, arguments: [String], environment: [String: String], directory: URL, timeout: TimeInterval) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            try Task.checkCancellation()
            guard Date() < deadline else { throw SignInError.timedOut }
            try await Task.sleep(for: .milliseconds(200))
        }
        return process.terminationStatus
    }
}
