import Domain

public extension QuotaMonitor {
    convenience init(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil,
        settingsRepository: (any ProviderSettingsRepository)? = nil,
        powerStateProvider: (any PowerStateProvider)? = SystemPowerStateProvider()
    ) {
        self.init(
            providers: providers,
            alerter: alerter,
            clock: SystemClock(),
            settingsRepository: settingsRepository,
            powerStateProvider: powerStateProvider
        )
    }
}
