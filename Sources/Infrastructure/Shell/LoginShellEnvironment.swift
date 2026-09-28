import Foundation

/// Resolves environment variables through the user's login shell.
///
/// GUI apps launched from Finder or login inherit launchd's environment, which
/// does not include variables exported in `~/.zshrc` / `~/.zprofile`. When a
/// `ProcessInfo` lookup misses, ask the user's login shell for the value.
struct LoginShellEnvironment: Sendable {
    private let cliExecutor: any CLIExecutor
    private let timeout: TimeInterval

    init(cliExecutor: any CLIExecutor, timeout: TimeInterval = 10.0) {
        self.cliExecutor = cliExecutor
        self.timeout = timeout
    }

    /// The name comes from user settings and is interpolated into the command
    /// string, so only valid shell identifiers are allowed through.
    static func isValidName(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Wraps the requested value in delimiters so rc-file noise (a stray `echo`
    /// in ~/.zshrc) can't be mistaken for the token. `printf` emits no trailing
    /// newline, so without delimiters noise would concatenate onto the value.
    static let beginMarker = "@@CLAUDEBAR_BEGIN@@"
    static let endMarker = "@@CLAUDEBAR_END@@"

    /// Reads an environment variable from the user's login shell.
    /// Returns nil when the name is invalid, the lookup fails, or the variable is unset or empty.
    func value(ofEnvVar name: String) async -> String? {
        guard Self.isValidName(name) else {
            AppLog.probes.debug("LoginShellEnvironment: invalid variable name, skipping login shell lookup")
            return nil
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        let binary = shell.isEmpty ? "/bin/zsh" : shell
        let command = "printf '\(Self.beginMarker)%s\(Self.endMarker)\\n' \"\(name)\""

        do {
            let result = try await cliExecutor.execute(
                binary: binary,
                args: ["-l", "-c", command],
                input: nil,
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [:]
            )
            return Self.parse(result.output, exitCode: result.exitCode, name: name)
        } catch {
            AppLog.probes.debug("LoginShellEnvironment: login shell lookup for \(name) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parse(_ output: String, exitCode: Int32, name: String) -> String? {
        guard exitCode == 0 else {
            AppLog.probes.debug("LoginShellEnvironment: lookup for \(name) exited with \(exitCode)")
            return nil
        }

        if let begin = output.range(of: beginMarker),
           let end = output.range(of: endMarker, range: begin.upperBound..<output.endIndex) {
            let value = String(output[begin.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                AppLog.probes.debug("LoginShellEnvironment: \(name) is not set in login shell")
                return nil
            }
            return value
        }

        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            AppLog.probes.debug("LoginShellEnvironment: \(name) is not set in login shell")
            return nil
        }
        return value
    }
}
