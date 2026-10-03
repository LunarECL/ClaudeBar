import SwiftUI
import Domain
import Infrastructure

/// OpenRouter provider configuration card for SettingsView.
/// Mirrors DeepSeekConfigCard — OpenRouter has a single global credits endpoint.
struct OpenRouterConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var openRouterConfigExpanded: Bool = false
    @State private var openRouterApiKeyInput: String = ""
    @State private var openRouterAuthEnvVarInput: String = ""
    @State private var showOpenRouterApiKey: Bool = false
    @State private var hasStoredOpenRouterApiKey: Bool = false
    @State private var isTestingOpenRouter = false
    @State private var openRouterTestResult: String?

    var body: some View {
        DisclosureGroup(isExpanded: $openRouterConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            openRouterConfigForm
        } label: {
            openRouterConfigHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        openRouterConfigExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    theme.glassBorder, theme.glassBorder.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            openRouterAuthEnvVarInput = settings.openrouter.openrouterAuthEnvVar()
            hasStoredOpenRouterApiKey = settings.openrouter.hasOpenRouterApiKey()
        }
    }

    private var openRouterConfigHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.42, blue: 1.0),
                                Color(red: 0.32, green: 0.22, blue: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenRouter Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Credit tracking")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var openRouterConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // API Key input
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("API KEY")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Spacer()

                    if hasStoredOpenRouterApiKey {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("Configured")
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        }
                        .foregroundStyle(theme.statusHealthy)
                    }
                }

                HStack(spacing: 6) {
                    Group {
                        if showOpenRouterApiKey {
                            TextField("", text: $openRouterApiKeyInput, prompt: Text("sk-or-...").foregroundStyle(theme.textTertiary))
                        } else {
                            SecureField("", text: $openRouterApiKeyInput, prompt: Text("sk-or-...").foregroundStyle(theme.textTertiary))
                        }
                    }
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.glassBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.glassBorder, lineWidth: 1)
                            )
                    )

                    Button {
                        showOpenRouterApiKey.toggle()
                    } label: {
                        Image(systemName: showOpenRouterApiKey ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(theme.glassBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Environment Variable
            VStack(alignment: .leading, spacing: 6) {
                Text("API KEY ENV VAR (ALTERNATIVE)")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                TextField("", text: $openRouterAuthEnvVarInput, prompt: Text("OPENROUTER_API_KEY").foregroundStyle(theme.textTertiary))
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.glassBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.glassBorder, lineWidth: 1)
                            )
                    )
                    .onChange(of: openRouterAuthEnvVarInput) { _, newValue in
                        settings.openrouter.setOpenRouterAuthEnvVar(newValue)
                    }
            }

            // Token lookup order
            VStack(alignment: .leading, spacing: 4) {
                Text("API KEY LOOKUP ORDER")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Text("1. First checks environment variable (default: OPENROUTER_API_KEY)")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                Text("2. Falls back to API key entered above")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            // Save & Test button
            if isTestingOpenRouter {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Testing connection...")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                Button {
                    Task {
                        await testOpenRouterConnection()
                    }
                } label: {
                    Text("Save & Test Connection")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.accentPrimary)
                        )
                }
                .buttonStyle(.plain)
            }

            if let result = openRouterTestResult {
                Text(result)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(result.contains("Success") ? theme.statusHealthy : theme.statusCritical)
            }

            // Help link
            VStack(alignment: .leading, spacing: 4) {
                Text("Get your API key from the OpenRouter platform")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)

                Link(destination: URL(string: "https://openrouter.ai/settings/keys")!) {
                    HStack(spacing: 3) {
                        Text("Open OpenRouter API Keys")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(theme.accentPrimary)
                }
            }

            // Delete API key
            if hasStoredOpenRouterApiKey {
                Button {
                    settings.openrouter.deleteOpenRouterApiKey()
                    hasStoredOpenRouterApiKey = false
                    openRouterApiKeyInput = ""
                    openRouterTestResult = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 9))
                        Text("Remove API Key")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    }
                    .foregroundStyle(theme.statusCritical)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func testOpenRouterConnection() async {
        isTestingOpenRouter = true
        openRouterTestResult = nil
        defer { isTestingOpenRouter = false }

        settings.openrouter.setOpenRouterAuthEnvVar(openRouterAuthEnvVarInput)
        let apiKey = openRouterApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            AppLog.credentials.info("Saving OpenRouter API key for connection test")
            settings.openrouter.saveOpenRouterApiKey(apiKey)
            hasStoredOpenRouterApiKey = true
            openRouterApiKeyInput = ""
        }

        guard let provider = monitor.provider(for: "openrouter") else {
            openRouterTestResult = "Failed: OpenRouter provider is not registered"
            return
        }

        guard await provider.isAvailable() else {
            openRouterTestResult = "Failed: No API key found"
            return
        }

        AppLog.credentials.info("Testing OpenRouter connection via provider refresh")
        do {
            _ = try await provider.refresh()
            AppLog.credentials.info("OpenRouter connection test succeeded")
            openRouterTestResult = "Success: Connection verified"
        } catch ProbeError.authenticationRequired {
            let message = "OpenRouter rejected the API key. Check you copied the whole key."
            AppLog.credentials.error("OpenRouter connection test failed: \(message)")
            openRouterTestResult = "Failed: \(message)"
        } catch {
            AppLog.credentials.error("OpenRouter connection test failed: \(error.localizedDescription)")
            openRouterTestResult = "Failed: \(error.localizedDescription)"
        }
    }
}
