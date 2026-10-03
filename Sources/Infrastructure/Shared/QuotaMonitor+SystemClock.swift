import Domain

public extension QuotaMonitor {
    convenience init(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil,
        settingsRepository: (any ProviderSettingsRepository)? = nil,
        powerStateProvider: (any PowerStateProvider)? = SystemPowerStateProvider(),
        settingsRepository: (any ProviderSettingsRepository)? = nil,
        statusPolicy: @escaping @MainActor () -> StatusPolicy = { .absolute }
    ) {
        self.init(
            providers: providers,
            alerter: alerter,
            clock: SystemClock(),
            settingsRepository: settingsRepository,
            powerStateProvider: powerStateProvider,
            settingsRepository: settingsRepository,
            statusPolicy: statusPolicy
        )
    }
}
