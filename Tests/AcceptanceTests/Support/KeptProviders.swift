@testable import Domain

/// A provider owns its logins and they end with it — `Account.provider` is
/// `unowned` (TARGET §12, slice 6). A test that holds only a login keeps
/// its provider here, as the app keeps every provider in `Providers`.
@MainActor private var keptProviders: [Provider] = []

@MainActor
func keep(_ provider: Provider) -> Provider {
    keptProviders.append(provider)
    return provider
}
