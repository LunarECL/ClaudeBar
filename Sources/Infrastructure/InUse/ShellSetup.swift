import Foundation

/// The shell lines behind *In use*: a function per CLI that reads the login
/// chosen in ClaudeBar (`~/.claudebar/in-use/<provider>`, see
/// `LoginsInUse`) and starts the CLI on that folder. An empty record runs the
/// CLI exactly as before. The lines live between two markers, so installing
/// twice writes them once and removing takes out nothing else; fish gets a
/// file of its own.
public struct ShellSetup: Sendable {
    /// A CLI the lines wrap: `claude`, started with `CLAUDE_CONFIG_DIR`.
    public struct Command: Sendable, Equatable {
        public let name: String
        public let variable: String
        public let providerId: String

        public init(name: String, variable: String, providerId: String) {
            self.name = name
            self.variable = variable
            self.providerId = providerId
        }
    }

    public enum Shell: String, CaseIterable, Sendable {
        case zsh, bash, fish

        /// The person's login shell, from `$SHELL` — zsh, macOS's own, when unknown.
        public static func login(_ path: String? = ProcessInfo.processInfo.environment["SHELL"]) -> Shell {
            let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            return Shell(rawValue: name) ?? .zsh
        }
    }

    static let begin = "# >>> claudebar in-use >>>"
    static let end = "# <<< claudebar in-use <<<"

    public let commands: [Command]
    public let home: URL

    public init(commands: [Command], home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.commands = commands
        self.home = home
    }

    /// Where the lines go. Terminal on macOS starts bash as a login shell,
    /// which reads `.bash_profile`.
    public func file(for shell: Shell) -> URL {
        switch shell {
        case .zsh: home.appendingPathComponent(".zshrc")
        case .bash: home.appendingPathComponent(".bash_profile")
        case .fish: home.appendingPathComponent(".config/fish/conf.d/claudebar-in-use.fish")
        }
    }

    public func isInstalled(_ shell: Shell) -> Bool {
        (try? String(contentsOf: file(for: shell), encoding: .utf8))?.contains(Self.begin) ?? false
    }

    /// The lines, as the setup sheet shows them and `install` writes them.
    public func block(for shell: Shell) -> String {
        let existing = (try? String(contentsOf: file(for: shell), encoding: .utf8)) ?? ""
        let body = commands.map { command -> String in
            let record = "$HOME/.claudebar/in-use/\(command.providerId)"
            if shell == .fish {
                return """
                function \(command.name)
                    set -l d (cat "\(record)" 2>/dev/null)
                    if test -n "$d"
                        \(command.variable)=$d command \(command.name) $argv
                    else
                        command \(command.name) $argv
                    end
                end
                """
            }
            // An alias always wins over a function, so one for this CLI is
            // replaced, and the function runs the program it named.
            let alias = Self.alias(command.name, in: existing.removingBlock())
            let program = alias ?? "command \(command.name)"
            return """
            \(alias == nil ? "" : "unalias \(command.name) 2>/dev/null\n")function \(command.name) {
              local d; d="$(cat "\(record)" 2>/dev/null)"
              if [ -n "$d" ]; then \(command.variable)="$d" \(program) "$@"; else \(program) "$@"; fi
            }
            """
        }
        let names = commands.map(\.name).joined(separator: " and ")
        return """
        \(Self.begin)
        # ClaudeBar → In use: new \(names) sessions start on the login chosen in ClaudeBar.
        # Delete this block, or turn it off in ClaudeBar's Settings, to go back.
        \(body.joined(separator: "\n"))
        \(Self.end)

        """
    }

    /// Writes the block, replacing any earlier one, and keeps the rest of the file.
    public func install(_ shell: Shell) throws {
        let url = file(for: shell)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let block = block(for: shell)
        let rest = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").removingBlock()
        let text = shell == .fish ? block : rest + (rest.isEmpty || rest.hasSuffix("\n") ? "" : "\n") + block
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Takes the block out — and fish's own file with it.
    public func remove(_ shell: Shell) throws {
        let url = file(for: shell)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        if shell == .fish {
            try FileManager.default.removeItem(at: url)
        } else {
            try Data(text.removingBlock().utf8).write(to: url, options: .atomic)
        }
    }

    /// The program an `alias name=…` line in `text` runs, the last one winning.
    static func alias(_ name: String, in text: String) -> String? {
        let pattern = #"(?m)^\s*alias\s+"# + NSRegularExpression.escapedPattern(for: name) + #"=(['"]?)(.+?)\1\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.matches(in: text, range: range).last,
              let value = Range(match.range(at: 2), in: text) else { return nil }
        return String(text[value])
    }
}

private extension String {
    /// The text without ClaudeBar's block.
    func removingBlock() -> String {
        guard let start = range(of: ShellSetup.begin),
              let end = range(of: ShellSetup.end, range: start.upperBound..<endIndex) else { return self }
        var after = end.upperBound
        if after < endIndex, self[after] == "\n" { after = index(after: after) }
        return String(self[..<start.lowerBound] + self[after...])
    }
}
