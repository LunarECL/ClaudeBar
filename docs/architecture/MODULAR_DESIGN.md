---
description: How ClaudeBar's code is cut into modules — one module per bounded context, the domain at each module's root and its implementations in Internal/, no Infrastructure layer and no vendor modules, one factory per module, the dependency rules, naming, testing, and where every folder of today's three targets goes; read before adding a file, a type or a module.
---

# ClaudeBar — the modular design

> [CANONICAL_MODEL.md](CANONICAL_MODEL.md) is the tree.
> [TARGET_ARCHITECTURE.md](TARGET_ARCHITECTURE.md) is how a provider runs —
> a JSON definition fetched by one `DataSource` type. **This document is the
> cut**: which module a file goes in, what a module shows and hides, and what
> it may import.
>
> **Status: PROPOSED.** Branch `refactor/provider-data-sources`. Today the
> code is three layers — `Domain`, `Infrastructure`, `App`. This design
> removes the middle one.

---

## 1 · Modules by context, not layers by technology

Today Codex is spread across all three layers: `Domain/Provider/Codex/`,
`Infrastructure/Codex/`, a settings protocol in `Domain/Provider/`, two
implementations in `Infrastructure/Storage/`, and a card in `App/`. A layer
groups code that changes for different reasons and splits code that changes
together.

The target cuts the other way: **one module per bounded context**, and inside
each module **two halves**:

```text
Modules/<Context>/
├── Sources/
│   ├── *.swift            THE DOMAIN — public values, aggregates, and the
│   │                      ports (protocols) for what lies outside the app
│   ├── <Context>.swift    THE FACTORY — a public enum that builds the
│   │                      context's objects and wires what they need
│   └── Internal/          THE IMPLEMENTATION — `internal` types that talk to
│                          a process, a socket, a file, the Keychain
├── Resources/             data the module ships (definitions, fixtures)
└── Tests/                 `@testable import` — Internal is reachable from here
```

**There is no Infrastructure layer.** An implementation lives next to the
domain it serves, in that module's `Internal/`, and Swift's `internal` access
level keeps it there: the App and every other module **cannot name it**. They
get a domain object from the module's factory.

**There are no vendor modules.** A vendor is a JSON file
([target §3](TARGET_ARCHITECTURE.md#3--codex-as-data)). The Swift behind it is
one `DataSource` type and a worker per case of its three closed sums, named
for a protocol or a format — all in `DataSources`.

```swift
// App — the composition root, in a few lines; it cannot construct an implementation
let settings = Storage.makeSettings()                     // → any ProviderSettingsRepository
let vault    = Storage.makeVault()                        // → any CredentialRepository
let catalog  = Providers.makeCatalog(settings: settings, vault: vault,
                                     cloudWatch: AWSClients.makeCloudWatch())
let monitor  = Monitoring.makeMonitor(providers: catalog.load())
```

## 2 · The modules

| Module | Context ([model §7](CANONICAL_MODEL.md#7--the-contexts-and-the-modules-that-implement-them)) | Public (the domain) | `Internal/` (the implementation) |
|---|---|---|---|
| `Quotas` | Quota · shared kernel | `UsageSnapshot`, `UsageQuota`, `QuotaType`, `QuotaStatus`, `UsagePace`, `CostUsage`, `BudgetStatus`, `AccountTier`, `ProbeError` | — none: pure values, no I/O |
| `DataSources` | Data Sources | `DataSource`, `DataSourceDefinition`, `Response`, `DataSourceError`, the closed sums `CredentialLookup` · `Fetch` · `Mapping`, `ConfigField`; the ports `CLIExecutor`, `NetworkClient`, `RPCTransport`, `CloudWatchClient`; the factory `DataSources.make(_:settings:vault:cloudWatch:)` | the workers — `Lookup/`, `Fetch/`, `Mapping/` — and the implementations of its own ports — `Process/`, `Network/` (§5) |
| `AWSClients` | Data Sources (SDK-backed) | `AWSClients.makeCloudWatch()` → `any CloudWatchClient` | the AWS SDK client and Bedrock pricing; the only module that links AWS |
| `Providers` | Providers · core | `Provider`, `AIProvider` (until it folds in), `ProviderDefinition`, `ProviderCatalog`, `ProviderAccount`, `ProviderSettingsRepository`, `CredentialRepository` | definition-file reading, `ExtensionDirectoryScanner`, `AIProviders` |
| `Providers/Resources/Providers/` | — | **the built-in definitions**: `codex.json`, `deepseek.json`, … | |
| `Monitoring` | Monitoring · conductor | `QuotaMonitor`, `MonitoringEvent`, `RefreshInterval`, `RefreshKind`, `Clock`, `PowerStateProvider` | `SystemClock`, `SystemPowerStateProvider`, `SingleFlightCache` |
| `Alerting` | Alerting | `QuotaAlerter`, Notify! values, `NotifySettingsRepository` | `NotificationAlerter`, `SystemAlertSender`, `NotifyGatewayClient` |
| `Activity` | Activity | `ClaudeSession`, `SessionEvent`, `SessionMonitor`, `NotchActivity`, `HookSettingsRepository` | `HookHTTPServer`, `HookInstaller`, `PortDiscovery`, `SessionEventParser` |
| `UsageHistory` | Usage History | `DailyUsageReport`, `DailyUsageStat`, `DailyUsageAnalyzing` | the JSONL analyzer, `SessionJSONLParser`, `ModelPricing` |
| `Storage` | Vault & Settings · generic | `Storage.makeSettings()`, `Storage.makeVault()`, `AppSettingsRepository` | `JSONSettingsRepository`, `JSONSettingsStore`, `KeychainCredentialRepository`, `UserDefaults…`, `SecureCredentialMigration` |
| `Diagnostics` | — cross-cutting | `AppLog` and its categories | `AppLogger`, `FileLogger` |
| `ClaudeBar` (App) | — the composition root | SwiftUI views, themes, menu-bar label, page state, the Add Provider sheet | — |

## 3 · The dependency rules

```text
                         ClaudeBar (App)
       ┌────────┬────────┬────┴─────┬──────────┬──────────┐
       ▼        ▼        ▼          ▼          ▼          ▼
  Monitoring Alerting Activity AWSClients  Storage   UsageHistory
       │        │                   │          │
       ▼        │                   ▼          ▼
   Providers ───┼──────────────▶ DataSources ◀─┘ (implements its ports)
       │        │                   │
       ▼        ▼                   ▼
   ┌──────────────── Quotas ────────────┐   (+ Diagnostics, which anyone may import)
```

1. **Arrows point at the supplier.** `Quotas` imports nothing but Foundation.
2. **Siblings never import across the fence.** `Monitoring` does not import
   `Alerting`; it emits `MonitoringEvent` and `Alerting` subscribes.
3. **No module names a vendor.** A vendor's name appears in its JSON file,
   in a test fixture folder, and in the App's visual identity until slice 3 —
   nowhere in a module's Swift.
4. **An SDK is linked by exactly one module.** AWS → `AWSClients`;
   SweetCookieKit, SwiftTerm, Subprocess → `DataSources`; Sparkle → the App.
5. **`internal` is the default.** A type is `public` only when another module
   must name it, and a public type is a word from the canonical model.
6. **Diagnostics is the only cross-cutting module.** It holds no rule.

The build enforces it: a forbidden import fails to compile, because the target
has no such dependency in `Project.swift`.

## 4 · Naming

| Rule | Example | Why |
|---|---|---|
| a public name is a word the screen prints, else the industry's | `DataSource` (*DATA SOURCE*), `CredentialLookup` (*TOKEN LOOKUP ORDER*), `Fetch` (*Data fetching method*), `CLIExecutor` (*CLI Mode*) | the model's rule, kept at the module boundary |
| a module is named for its context, a type for its node | module `Providers`, type `Provider` | |
| **no type has its module's name** | `Quotas` holds `UsageQuota`, never a type `Quotas` | `Quotas.Quotas` breaks qualification in Swift |
| no module shadows an Apple or package module | not `Settings` (SwiftUI's scene), not `Logging` (swift-log, pulled in by the AWS SDK), not `ActivityKit` | |
| **a worker is named for its protocol, format or place — never a vendor** | `JSONRPCFetcher`, `OAuth2Refresher`, `JSONFileReader` | a vendor-named type is a vendor's five jobs coming back |
| a port is the domain word; its implementation names the technology | `NetworkClient` → `URLSessionNetworkClient` | |
| no grab-bag types | no `Machines`, `Context`, `Dependencies`, `Environment` bundle: each worker receives the one thing it uses | a bag is an ISP violation with a friendly name |
| a factory is the module's name as an enum | `enum DataSources { static func make(…) }` | |

## 5 · Inside a module

```text
Modules/DataSources/
├── Sources/
│   ├── DataSource.swift              ◆ fetchResponse() · fetchUsage() · isReady — one type for every provider
│   ├── Response.swift                ◇ status · headers · body — what Test Connection shows
│   ├── DataSourceError.swift         step: lookup · fetch · mapping
│   ├── DataSourceDefinition.swift    ◇ kind · credential · fetch · mapping · fallback — Codable
│   ├── CredentialLookup.swift        ◇ enum: environment · setting · jsonFile · keychain ·
│   │                                   browserCookie · refreshing(_, oauth2)
│   ├── Fetch.swift                   ◇ enum: http · jsonRpc · cli · terminal · file · script ·
│   │                                   cloudWatch
│   ├── Mapping.swift                 ◇ enum: json · text
│   ├── CLIExecutor.swift             port, @Mockable
│   ├── NetworkClient.swift           port, @Mockable
│   ├── RPCTransport.swift            port, @Mockable
│   ├── CloudWatchClient.swift        port, @Mockable — implemented in AWSClients
│   ├── DataSources.swift             the factory: make(_:settings:vault:cloudWatch:)
│   └── Internal/
│       ├── Lookup/    EnvironmentReader · SettingReader · JSONFileReader · KeychainReader ·
│       │              BrowserCookieReader · OAuth2Refresher
│       ├── Fetch/     HTTPFetcher · JSONRPCFetcher · CLIFetcher · TerminalFetcher ·
│       │              FileFetcher · ScriptFetcher · CloudWatchFetcher
│       ├── Mapping/   JSONMapper (+ the path dialect) · TextMapper
│       ├── Process/   DefaultCLIExecutor · ProcessRPCTransport · InteractiveRunner ·
│       │              BinaryLocator · LoginShellEnvironment · TerminalRenderer
│       └── Network/   URLSessionNetworkClient
└── Tests/
    ├── Fetch/JSONRPCFetcherTests.swift
    ├── Mapping/JSONMapperTests.swift  one test per mapping feature
    └── DataSourceTests.swift          look up → fetch → map, the 401 refresh
```

```text
Modules/Providers/
├── Sources/
│   ├── Provider.swift                  ◆ the lifecycle, and the fallback between data sources
│   ├── ProviderDefinition.swift        ◇ the definition and its laws
│   ├── ProviderCatalog.swift           built in · custom · extension; add · import · export
│   ├── ProviderSettingsRepository.swift  port, @Mockable
│   ├── CredentialRepository.swift      port, @Mockable
│   ├── Providers.swift                 the factory: makeCatalog(settings:vault:cloudWatch:)
│   └── Internal/
│       └── DefinitionFiles.swift       reads *.json from Bundle.module or a folder
├── Resources/Providers/                codex.json · deepseek.json · …   — the vendors
└── Tests/
    ├── ProviderTests.swift
    ├── CatalogTests.swift              every bundled definition decodes
    └── Golden/codex/                   recorded responses → expected snapshots
```

## 6 · Ports: as many as the requirement, and no more

A port (a `public protocol` at a module's root) exists because the domain
needs something outside the app that it must not build itself. Each is named
for that thing, is `@Mockable`, and has its implementation in an `Internal/`.

| Port | Declared in | What lies outside | Implemented in |
|---|---|---|---|
| `CLIExecutor` | DataSources | a CLI, run to completion | `DataSources/Internal/Process` |
| `NetworkClient` | DataSources | an HTTP endpoint | `DataSources/Internal/Network` |
| `RPCTransport` | DataSources | a JSON-RPC pipe to a process | `DataSources/Internal/Process` |
| `CloudWatchClient` | DataSources | AWS CloudWatch | `AWSClients` |
| `ProviderSettingsRepository` · `CredentialRepository` | Providers | `settings.json`, the Keychain | `Storage` |
| `Clock` · `PowerStateProvider` | Monitoring | time, the battery | `Monitoring/Internal` |
| `QuotaAlerter` | Alerting | the user's notifications | `Alerting/Internal` |
| `HookEventReceiver` | Activity | Claude Code's hooks | `Activity/Internal` |

Not a port: a definition (it is parsed, not injected), a closed sum's worker
(the factory picks it; tests build it with `@testable`), a module's own
aggregate (views call `Provider` directly), or anything added "for
testability" alone.

## 7 · Testing

- One test target per module: `QuotasTests`, `DataSourcesTests`, `ProvidersTests` …
  A module's tests link only that module and its suppliers, so `QuotasTests`
  no longer links six AWS SDKs.
- Workers are tested alone, built with `@testable` and a mocked port.
  Definitions are tested by **golden fixtures** — the responses today's probes
  are tested with, run through the JSON, must give today's snapshots.
- Chicago school, unchanged: stub ports with Mockable, assert on state.
- `AcceptanceTests` stays at the App level and composes real modules with
  stubbed ports.
- `MOCKING` is a project-level compilation condition in `Project.swift`, so
  every new target inherits it.

## 8 · Where today's code goes

| Today | Goes to |
|---|---|
| `Domain/Provider/` kernel files | `Quotas` |
| `Domain/Provider/` page state (`MenuBarLabel`, `MenuBar*Display`, `MenuBarStackedSize`, `CountdownColon`, `PopoverContentHeight`, `UsageDisplayMode`, `ProviderBadgeState`) | the App |
| `Domain/Provider/AIProvider.swift`, `AIProviderRepository`, `ProviderAccount`, `MultiAccount*`, `ProviderSettingsRepository`, `CredentialRepository`, `AccountInfo` | `Providers` |
| `Domain/Provider/<Vendor>/` (`XxxProvider`, `XxxProbeMode`) | **deleted** — the lifecycle is `Provider`, the modes are the definition's `dataSources` |
| `Infrastructure/<Vendor>/` (`XxxUsageProbe`, `XxxCredentialLoader`, `DefaultXxxRPCClient`, …) | **deleted** — URLs, paths, fields and arguments move into `<vendor>.json`; any reusable mechanism they contain becomes a worker in `DataSources/Internal` |
| `Infrastructure/Bedrock/` | `AWSClients` (CloudWatch, pricing) behind `CloudWatchClient` |
| `Infrastructure/Shared/`, `Shell/`, `Network/` | `DataSources/Internal/Process` and `Network` (the ports at its root); `SystemClock`, `SystemPowerStateProvider`, `SingleFlightCache`, `QuotaMonitor+SystemClock` → `Monitoring/Internal`; `SystemAlertSender` → `Alerting/Internal` |
| `Domain/Extension/`, `Infrastructure/Extension/` | `Providers` (a manifest is read as a definition) and `DataSources` (`Fetch.script`, `SectionData` as a mapping, `HealthCheckProbe` as an `http` fetch) |
| `Domain/Monitor/` | `Monitoring` (`QuotaAlerter` → `Alerting`) |
| `Domain/Notify/`, `Infrastructure/Notifications/`, `Notify/` | `Alerting` |
| `Domain/Session/`, `Domain/Notch/`, `Infrastructure/Hooks/` | `Activity` (`NSScreen+NotchMetrics` → App) |
| `Domain/DailyUsage/`, Claude's JSONL analyzer and pricing | `UsageHistory` |
| `Domain/Settings/`, `Infrastructure/Storage/` | `Storage` (`StatusColorPolicy`, `MenuBarProviderSettings` → App; `AIProviders` → `Providers`) |
| `Infrastructure/Logging/` | `Diagnostics` |
| `Infrastructure/TerminalImport/` | the App — themes are presentation |
| `Tests/DomainTests`, `InfrastructureTests` | split per module, following their sources |

## 9 · How we get there without a big bang

New modules appear underneath `Domain` and `Infrastructure`, which
**re-export** them (`@_exported import Quotas`), so no call site changes while
files move. When an old target is empty it is deleted.

| Step | Moves | Visible change |
|---|---|---|
| **M0** | `Diagnostics` and `Quotas` carved; `Domain` re-exports `Quotas` | none |
| **M1** | `DataSources` — the ports and their implementations move in; `DataSource`, the closed sums and the workers Codex needs are written test-first | none |
| **M2** | `Providers` — `Provider`, the definition, the catalog; `codex.json` with golden tests; the App builds Codex from it; `CodexProvider` and every `Codex*` type in `Infrastructure/Codex` deleted. **Slice 1 of the target architecture** | none |
| M3… | one group of providers per PR (target §8); then `Monitoring`, `Alerting`, `Activity`, `UsageHistory`, `Storage` | none |
| last | `Domain` and `Infrastructure` are empty and removed from `Project.swift` | none |

The order is forced by the imports: `Provider` needs `UsageSnapshot`
(Quotas), and the workers need the port implementations
(`DefaultCLIExecutor`, `ProcessRPCTransport`, `URLSessionNetworkClient`) to be
in `DataSources` before Codex's code can be deleted.

## 10 · Open

- **`Storage` as a module, or each module's settings in its own `Internal/`?**
  `settings.json` is one file many contexts write, so one owner today.
- **One module per heavy SDK.** AWS is the only one today; the next gets its
  own `…Clients` module behind its own port in `DataSources`.
- **`AIProvider` beside `Provider`** until the last provider moves — then the
  protocol folds in.
