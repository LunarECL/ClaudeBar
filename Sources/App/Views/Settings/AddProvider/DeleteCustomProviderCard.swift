import SwiftUI
import Domain
import Infrastructure
import Providers

/// *Delete* a provider someone made: its definition file and its saved key go,
/// and it leaves the lineup. Built-ins can only be disabled.
struct DeleteCustomProviderCard: View {
    let provider: Provider
    let monitor: QuotaMonitor
    let onDeleted: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var confirming = false
    @State private var error: String?

    var body: some View {
        SettingsCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom provider")
                        .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                    Text("Deleting removes it from ClaudeBar and forgets its saved key.")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                    if let error {
                        Text(error)
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.statusWarning)
                    }
                }
                Spacer()
                Button("Delete Provider…", role: .destructive) { confirming = true }
            }
        }
        .confirmationDialog("Delete \(provider.name)?", isPresented: $confirming) {
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private func delete() {
        do {
            try ProviderCatalog().remove(provider.id)
        } catch {
            self.error = error.localizedDescription
            return
        }
        ProviderVault().delete("apiKey", provider: provider.id)
        for account in provider.accounts {
            monitor.removeProvider(id: account.id)
        }
        Providers.unregister(custom: provider.id)
        onDeleted()
    }
}
