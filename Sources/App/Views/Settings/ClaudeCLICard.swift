import SwiftUI
import Domain

/// Claude's CLI binary — the executable the CLI data sources and the
/// guest-pass probe run. For installs where `claude` lives under another
/// name or path (#210). The value is only ever a subprocess argv[0], never
/// a shell command line, so aliases and shell functions cannot work.
/// Applied when the app starts; the next launch picks a change up.
struct ClaudeCLICard: View {
    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var expanded = false
    @State private var binaryInput = ""

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            form
        } label: {
            header
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.toggle()
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
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            binaryInput = settings.claude.claudeBinary()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.45, green: 0.45, blue: 0.50),
                                Color(red: 0.30, green: 0.30, blue: 0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "terminal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude CLI Binary")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Where the claude command lives")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CLI BINARY")
                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .tracking(0.5)

            TextField("", text: $binaryInput, prompt: Text("claude").foregroundStyle(theme.textTertiary))
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
                .onChange(of: binaryInput) { _, newValue in
                    settings.claude.setClaudeBinary(newValue)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("Leave empty to use `claude` from PATH.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)

                Text("Enter a full binary path (e.g. /opt/tools/bin/claude-work) or a name findable in PATH. Shell aliases and functions (c, claudel…) cannot be launched by another app — point this at the real binary they call. A change applies the next time ClaudeBar starts.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
