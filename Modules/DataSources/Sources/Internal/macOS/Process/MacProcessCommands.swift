#if os(macOS)
import Foundation

extension Platform {
    static let macScriptCommand: ScriptCommand = { run in ["/bin/sh", "-c", run] }

    static let macLoginShellCommand: LoginShellCommand = { variable in
        let preferred = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        let binary = preferred.isEmpty ? "/bin/zsh" : preferred
        // Interactive login shell sources both rc and profile files.
        let command = "printf '\(LoginShellEnvironment.beginMarker)%s\(LoginShellEnvironment.endMarker)\\n' \"$\(variable)\""
        return [binary, "-l", "-i", "-c", command]
    }

    static let macLocalServer: LocalServerFactory = { call, commands, network, processPaths in
        LocalServerFetcher(call: call, commands: commands, network: network, processPaths: processPaths)
    }

    static let macLocalServerCommands: LocalServerCommands = { process in
        [LocalServerFetcher.processQuery(process), LocalServerFetcher.listeningPortsQuery(pid: "{{pid}}")]
    }
}
#endif
