import SwiftUI
import AppKit
import Domain
import Providers

/// Under a product's account chips: which login new terminal sessions start
/// with, as a menu to change it — or the login worth moving to — or, while a
/// choice waits for the shell lines, the setup. The rules are the domain's
/// (`NewSessions`, `Provider`, `Account`); this only shows them.
struct InUseStrip: View {
    let provider: Provider
    @Environment(NewSessions.self) private var sessions
    @Environment(\.appTheme) private var theme
    private var settings: AppSettings { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sessions.isWaiting(in: provider) {
                InUseSetupCard()
            } else if let better = provider.suggestedLogin {
                suggestion(to: better)
            } else {
                line
            }
            if let problem = sessions.problem {
                Text(problem)
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.statusCritical)
            }
        }
    }

    /// "New terminal sessions use personal ▾" — the menu that changes it.
    private var line: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
            Text("New terminal sessions use")
            Menu {
                ForEach(provider.loginsForNewSessions, id: \.id) { login in
                    Button { sessions.use(login) } label: {
                        if login.isInUse {
                            Label(settings.shown(login.displayName), systemImage: "checkmark")
                        } else {
                            Text(settings.shown(login.displayName))
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(settings.shown(provider.inUse.displayName)).fontWeight(.bold)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(theme.textPrimary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
        .foregroundStyle(theme.textTertiary)
        .help("Claude Desktop and IDE extensions keep their own login. Sessions already running keep theirs.")
    }

    private func suggestion(to better: Account) -> some View {
        let left = better.snapshot?.lowestQuota.map { " has \(Int($0.percentRemaining))% left" } ?? " has more left"
        return HStack(spacing: 8) {
            Image(systemName: "terminal.fill").foregroundStyle(theme.statusWarning)
            Text("\(settings.shown(provider.inUse.displayName)) is low — \(settings.shown(better.displayName))\(left)")
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            InUseButton(title: "Use for New Sessions", prominent: true) { sessions.use(better) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.statusWarning.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.statusWarning.opacity(0.4), lineWidth: 1))
    }
}

/// The one-time setup: the lines ClaudeBar adds to the shell, shown before
/// they are written.
struct InUseSetupCard: View {
    @Environment(NewSessions.self) private var sessions
    @Environment(\.appTheme) private var theme

    var body: some View {
        @Bindable var sessions = sessions
        VStack(alignment: .leading, spacing: 8) {
            Text("Let ClaudeBar choose the login?")
                .font(.system(size: 13, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text("One time: ClaudeBar adds these lines to your shell. Each time you run \(sessions.products.compactMap(\.terminalCommand?.name).joined(separator: " or ")), they start on the login you chose here. Delete them to turn this off.")
                .font(.system(size: 11, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                ForEach(LoginShell.allCases, id: \.self) { shell in
                    InUseButton(title: shell.rawValue, prominent: sessions.shell == shell) { sessions.shell = shell }
                }
            }
            ScrollView {
                Text(sessions.lines)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 130)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.glassBackground))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            HStack(spacing: 6) {
                InUseButton(title: "Add to \(sessions.file.abbreviatingHome)", prominent: true) { sessions.setUp() }
                InUseButton(title: "Copy — I'll Add It", prominent: false) {
                    let lines = sessions.setUpByHand()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines, forType: .string)
                }
                Spacer(minLength: 0)
                InUseButton(title: "Cancel", prominent: false) { sessions.cancel() }
            }
            Text("Terminals already open pick it up in a new tab.")
                .font(.system(size: 10, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
    }
}

/// Settings → Accounts: which login new terminal sessions use, the shell
/// lines that make it work, and *Switch when low*.
struct InUseSettingsSection: View {
    @Bindable var provider: Provider
    @Environment(NewSessions.self) private var sessions
    @Environment(\.appTheme) private var theme
    @State private var settingUp = false
    private var settings: AppSettings { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Image(systemName: "terminal").foregroundStyle(theme.textSecondary)
                Text("New terminal sessions").font(.subheadline.bold()).foregroundStyle(theme.textPrimary)
                Spacer()
                Menu {
                    ForEach(provider.loginsForNewSessions, id: \.id) { login in
                        Button(settings.shown(login.displayName)) { sessions.use(login) }.disabled(login.isInUse)
                    }
                } label: {
                    Text(settings.shown(provider.inUse.displayName))
                }
                .fixedSize()
            }
            Text("Which login `\(provider.terminalCommand?.name ?? provider.id)` starts with in your terminal. Sessions already running keep theirs; Claude Desktop and IDE extensions keep their own login.")
                .font(.caption).foregroundStyle(theme.textSecondary)

            if sessions.isWaiting(in: provider) || settingUp {
                InUseSetupCard()
                    .onChange(of: sessions.isSetUp) { _, done in if done { settingUp = false } }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: sessions.isSetUp ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(sessions.isSetUp ? theme.statusHealthy : theme.textTertiary)
                    Text(sessions.isSetUp ? "LoginShell set up in \(sessions.file.abbreviatingHome)" : "LoginShell not set up yet")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                    Spacer()
                    if sessions.isSetUp {
                        Button("Remove") { sessions.turnOff() }.controlSize(.small)
                    } else {
                        Button("Set Up…") { settingUp = true }.controlSize(.small)
                    }
                }
            }

            Toggle(isOn: $provider.switchesWhenLow) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Switch when low").foregroundStyle(theme.textPrimary)
                    Text("New sessions move to the ticked login with the most left, and ClaudeBar tells you each time.")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                }
            }
            .toggleStyle(.switch)

            if provider.switchesWhenLow {
                HStack {
                    Text("When the login in use drops below").font(.caption).foregroundStyle(theme.textSecondary)
                    Picker("", selection: $provider.switchBelow) {
                        ForEach([5, 10, 20, 30], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                ForEach(provider.loginsForNewSessions, id: \.id) { login in
                    Toggle(settings.shown(login.displayName), isOn: Binding(
                        get: { provider.mayPick(login) },
                        set: { provider.setMayPick($0, login) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
            }
        }
    }
}

/// A small capsule button in the theme's colours.
struct InUseButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: theme.fontDesign))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(prominent ? theme.textPrimary : theme.textSecondary)
                .background(Capsule().fill(prominent ? theme.accentPrimary.opacity(0.22) : theme.glassBackground))
                .overlay(Capsule().stroke(prominent ? theme.accentPrimary.opacity(0.6) : theme.glassBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private extension URL {
    /// `~/.zshrc` rather than `/Users/you/.zshrc`.
    var abbreviatingHome: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
