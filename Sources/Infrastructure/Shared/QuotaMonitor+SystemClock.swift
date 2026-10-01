import Domain

public extension QuotaMonitor {
    convenience init(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil,
        powerStateProvider: (any PowerStateProvider)? = SystemPowerStateProvider(),
        statusPolicy: @escaping @MainActor () -> StatusPolicy = { .absolute }
    ) {
        self.init(
            providers: providers,
            alerter: alerter,
            clock: SystemClock(),
            powerStateProvider: powerStateProvider,
            statusPolicy: statusPolicy
        )
    }
}
