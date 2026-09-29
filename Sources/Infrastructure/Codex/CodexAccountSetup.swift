import Foundation
import Domain

/// Links an existing, independently authenticated Codex home. Only metadata and
/// the directory are persisted by ClaudeBar; credentials remain owned by Codex.
public enum CodexAccountSetup {
    public static func configuration(
        codexHome: String,
        existingAccounts: [ProviderAccountConfig],
        defaultCodexHome: String = (CodexCredentialLoader().authFilePath as NSString).deletingLastPathComponent
    ) throws -> ProviderAccountConfig {
        let home = URL(fileURLWithPath: codexHome).standardizedFileURL.resolvingSymlinksInPath().path
        let defaultHome = URL(fileURLWithPath: defaultCodexHome).standardizedFileURL.resolvingSymlinksInPath().path
        guard home != defaultHome else {
            throw ProbeError.executionFailed("This is the default Codex login, which is already listed.")
        }
        let loader = CodexCredentialLoader(codexHome: home)
        guard let credentials = loader.loadCredentials(),
              let accountId = credentials.accountId, !accountId.isEmpty,
              let email = credentials.email else {
            throw ProbeError.executionFailed("No ChatGPT account found in this folder. Sign in with Codex using file credential storage, then choose the folder again.")
        }
        let defaultAccountId = CodexCredentialLoader(codexHome: defaultHome).loadCredentials()?.accountId
        guard accountId != defaultAccountId,
              !existingAccounts.contains(where: {
                  $0.probeConfig["chatgptAccountId"] == accountId ||
                  $0.probeConfig["codexHome"].map {
                      URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path == home
                  } == true
              }) else {
            throw ProbeError.executionFailed("This Codex account is already listed.")
        }
        return ProviderAccountConfig(
            accountId: UUID().uuidString.lowercased(), label: "", email: email,
            probeConfig: ["codexHome": home, "chatgptAccountId": accountId]
        )
    }

    @MainActor
    public static func provider(
        configuration: ProviderAccountConfig,
        settingsRepository: any CodexSettingsRepository
    ) -> CodexProvider? {
        guard configuration.accountId != ProviderAccount.defaultAccountId,
              let home = configuration.probeConfig["codexHome"], home.hasPrefix("/"),
              let accountId = configuration.probeConfig["chatgptAccountId"], !accountId.isEmpty else { return nil }
        let loader = CodexCredentialLoader(codexHome: home)
        return CodexProvider(
            rpcProbe: CodexAccountUsageProbe(
                probe: CodexUsageProbe(client: DefaultCodexRPCClient(codexHome: home, includeAccountIdentity: true)),
                credentialLoader: loader, expectedAccountId: accountId),
            apiProbe: CodexAccountUsageProbe(
                probe: CodexAPIUsageProbe(credentialLoader: loader),
                credentialLoader: loader, expectedAccountId: accountId),
            settingsRepository: settingsRepository,
            account: configuration.toProviderAccount(providerId: "codex")
        )
    }
}

/// Guards against a directory being reauthenticated to a different account and
/// adds email metadata to both probe modes. JWT email is only a display hint.
public struct CodexAccountUsageProbe: UsageProbe {
    private let underlyingProbe: any UsageProbe
    private let credentialLoader: CodexCredentialLoader
    private let expectedAccountId: String?

    public init(probe: any UsageProbe, credentialLoader: CodexCredentialLoader = CodexCredentialLoader(),
                expectedAccountId: String? = nil) {
        self.underlyingProbe = probe
        self.credentialLoader = credentialLoader
        self.expectedAccountId = expectedAccountId
    }

    public func isAvailable() async -> Bool {
        if let expectedAccountId,
           credentialLoader.loadCredentials()?.accountId != expectedAccountId { return false }
        return await underlyingProbe.isAvailable()
    }

    public func probe() async throws -> UsageSnapshot {
        try validateIdentity()
        let snapshot = try await underlyingProbe.probe()
        try validateIdentity()
        return UsageSnapshot(
            providerId: snapshot.providerId, quotas: snapshot.quotas, capturedAt: snapshot.capturedAt,
            accountEmail: snapshot.accountEmail ?? credentialLoader.loadCredentials()?.email,
            accountOrganization: snapshot.accountOrganization, loginMethod: snapshot.loginMethod,
            accountTier: snapshot.accountTier, costUsage: snapshot.costUsage,
            bedrockUsage: snapshot.bedrockUsage, dailyUsageReport: snapshot.dailyUsageReport,
            extensionMetrics: snapshot.extensionMetrics
        )
    }

    private func validateIdentity() throws {
        guard let expectedAccountId else { return }
        guard credentialLoader.loadCredentials()?.accountId == expectedAccountId else {
            throw ProbeError.sessionExpired(hint: "Sign in to the original account in this Codex folder, or remove it and add the new account in Settings.")
        }
    }
}
