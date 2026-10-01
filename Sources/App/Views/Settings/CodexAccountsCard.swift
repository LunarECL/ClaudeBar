import SwiftUI
import AppKit
import Domain
import Infrastructure
import Providers

/// Email identifies the login; users never need to invent an account name.
struct CodexAccountsCard: View {
    let monitor: QuotaMonitor
    @Environment(\.appTheme) private var theme
    @State private var showingSetup = false

    private var accounts: [Provider] {
        monitor.allProviders.compactMap { $0 as? Provider }.filter { $0.definition.id == "codex" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex Accounts")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)

            ForEach(accounts, id: \.id) { provider in
                HStack(alignment: .top, spacing: 10) {
                    ProviderIconView(providerId: provider.id, size: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.accountEmail ?? "Default Codex login")
                            .font(.body)
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                        Text(provider.account.isDefault ? "Uses your default Codex login" : "Separate Codex login")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if !provider.account.isDefault {
                        Button("Remove") { remove(provider) }
                            .accessibilityLabel("Remove \(provider.name) from ClaudeBar")
                    }
                }
            }

            Text("Each account has its own quota display. Select both in Menu Bar settings to keep both visible.")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)

            Button("Add Codex Account…") { showingSetup = true }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius).fill(theme.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.glassBorder, lineWidth: 1))
        .sheet(isPresented: $showingSetup) {
            CodexAccountSetupSheet(monitor: monitor)
                .environment(\.appTheme, theme)
        }
    }

    private func remove(_ provider: Provider) {
        JSONSettingsRepository.shared.removeAccount(accountId: provider.account.accountId, forProvider: "codex")
        let settings = AppSettings.shared
        let remaining = settings.menuBarProviderIds.filter { $0 != provider.id }
        settings.setMenuBarProviderIds(remaining.isEmpty ? ["codex"] : remaining)
        if monitor.selectedProviderId == provider.id { monitor.selectedProviderId = "codex" }
        monitor.removeProvider(id: provider.id)
    }
}

private struct CodexAccountSetupSheet: View {
    let monitor: QuotaMonitor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var error: String?
    @State private var copied = false
    @State private var home = NSHomeDirectory() + "/.codex-claudebar/" + UUID().uuidString.lowercased()

    private var loginCommand: String {
        let quoted = "'" + home.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "mkdir -p \(quoted) && chmod 700 \(quoted) && CODEX_HOME=\(quoted) codex -c 'cli_auth_credentials_store=\"file\"' login"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Codex Account")
                .font(.title2.weight(.semibold))
            Text("Sign in once in a separate Codex folder. ClaudeBar reads the account’s email automatically.")

            Text("1. Copy this command and run it in Terminal.")
                .font(.headline)
            Text(loginCommand)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button(copied ? "Copied" : "Copy Login Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(loginCommand, forType: .string)
                copied = true
            }

            Text("2. In the browser, sign in to the account you want to add. Check the email before continuing.")
            Text("3. Choose the folder after sign-in finishes. You can also choose an existing Codex folder that uses file credential storage.")
            Text("Removing an account from ClaudeBar leaves its Codex login and files in place.")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)

            if let error {
                Text(error)
                    .foregroundStyle(theme.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Could not add account: \(error)")
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Signed-in Folder…", action: chooseFolder)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .foregroundStyle(theme.textPrimary)
        .background(theme.backgroundGradient)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: home)
        panel.prompt = "Add Account"
        panel.message = "Choose the Codex folder containing auth.json."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let settings = JSONSettingsRepository.shared
                let config = try AddedAccounts.configuration(
                    "codex", folder: url.path, existing: settings.accounts(forProvider: "codex"))
                guard let provider = AddedAccounts.provider("codex", configuration: config, settings: settings) else {
                    return
                }
                settings.addAccount(config, forProvider: "codex")
                monitor.addProvider(provider)
                Task { await monitor.refresh(providerId: provider.id) }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
