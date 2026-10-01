---
description: The architecture that implements the canonical model — a provider as a JSON definition, one DataSource type that fetches for every provider through single-job internal workers, no vendor-named code, the runtime from definition to popover, settings keys, testing, and the migration slices starting with Codex; read before moving a provider to JSON or adding a fetch, mapping or credential case.
---

# ClaudeBar — the target architecture

> [CANONICAL_MODEL.md](CANONICAL_MODEL.md) says WHAT the domain is.
> [MODULAR_DESIGN.md](MODULAR_DESIGN.md) says which module each file lives in.
> **This document says how a provider runs**: from a JSON file, through one
> `DataSource`, to the popover — and in what order today's code gets there.
>
> **Status: PROPOSED.** Branch `refactor/provider-data-sources`. Today's
> wiring is [ARCHITECTURE.md](ARCHITECTURE.md); it stays the truth until a
> slice below lands, and each slice updates it.

---

## 1 · The goal, as two principles

| Principle | Today | Target |
|---|---|---|
| **SRP** — one reason to change | `CodexAPIUsageProbe` changes when the auth file moves, when OAuth refresh changes, when the URL changes, when a header changes, and when the JSON changes. Twenty providers repeat this, each with its own `XxxProvider` lifecycle on top | a **definition** changes when Codex changes. A **worker** changes when its protocol or format changes. **`Provider`** changes when the lifecycle changes. Nothing else |
| **OCP** — open for extension, closed for modification | adding a provider adds ~5 types and edits ~10 files | adding a provider adds **one JSON file**. Adding a protocol or format adds **one case and one worker** to a closed list. Neither touches another provider |

There is no `UsageProbe`, no `XxxUsageProbe`, no `XxxProvider`, no
`XxxCredentialLoader`, and no vendor module. Vendor knowledge — URLs, file
paths, field names, client ids, CLI arguments — is data.

## 2 · The pieces

```text
  codex.json  ─────────────────────────────────────────────────┐   DATA
  deepseek.json · ~/.claudebar/providers/*.json · extensions   │   (what Codex IS)
                                                               ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ ProviderCatalog      reads files → [ProviderDefinition]                  │
│ Providers.make(_:)   definition → Provider, each data source made live   │
│                      by DataSources.make(_:settings:vault:cloudWatch:)   │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ Provider ◆  THE lifecycle: isEnabled · active data source · fallback ·   │
│             isSyncing · usage · lastError · refresh() · use(kind)        │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │ refresh → activeDataSource.fetchUsage()
                                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ DataSource ◆  ONE type for every provider: its definition + only the     │
│               connection its fetch needs. fetchUsage() = look up the     │
│               key → fetch → map. isReady. Never knows a vendor           │
└───────┬──────────────────────────┬──────────────────────────┬────────────┘
        ▼                          ▼                          ▼
  CredentialLookup (enum)     Fetch (enum)               Mapping (enum)
  each case's worker:         each case's worker:        each case's worker:
  EnvironmentReader           HTTPFetcher                JSONMapper
  SettingReader               JSONRPCFetcher             TextMapper
  JSONFileReader              CLIFetcher
  KeychainReader              TerminalFetcher
  BrowserCookieReader         FileFetcher
  OAuth2Refresher (refresh)   ScriptFetcher
                              CloudWatchFetcher ── CloudWatchClient (port; AWSClients)
        │                          │
        ▼                          ▼
  settings · vault            NetworkClient · CLIExecutor · RPCTransport
  (passed in by name)         (the module's own, built by its factory)
```

| Piece | One job | Changes when |
|---|---|---|
| `ProviderDefinition` · `DataSourceDefinition` | the provider as data, validated on load | a vendor changes |
| `Provider` | the lifecycle every provider shares, and the fallback between its data sources | the lifecycle changes |
| `DataSource` | fetches one data source's usage: look up the key, fetch, map | the order of those three changes |
| `CredentialLookup` · `Fetch` · `Mapping` | closed sums — one case per JSON tag | a protocol, format or key location is added |
| a worker (`HTTPFetcher`, `JSONMapper`, `OAuth2Refresher`, …) | carries out one case | that protocol or format changes |
| `DataSources.make(_:settings:vault:cloudWatch:)` | the one place a case meets the connection it needs | a connection is added |

## 3 · Codex, as data

`Resources/Providers/codex.json` — the whole of Codex. The fields below are the
ones today's two probes hard-code; slice 1 pins every one of them with a test
against the current probes' fixtures before those probes are deleted.

```json
{
  "id": "codex",
  "name": "Codex",
  "cli": "codex",
  "links": { "dashboard": "https://platform.openai.com/usage",
             "status": "https://status.openai.com" },
  "enabledByDefault": true,
  "defaultDataSource": "rpc",
  "dataSources": [
    {
      "kind": "rpc", "label": "RPC", "summary": "Uses codex app-server RPC",
      "fetch": { "jsonRpc": {
        "cli": "codex", "args": ["-s", "read-only", "-a", "never", "app-server"],
        "workingDirectory": "probe",
        "handshake": [
          { "request": "initialize", "params": { "clientInfo": { "name": "claudebar", "version": "1.0.0" } } },
          { "notify": "initialized" } ],
        "call": "account/rateLimits/read" } },
      "mapping": { "json": {
        "plan": "$.result.rateLimits.planType",
        "quotas": [
          { "name": "Session", "at": "$.result.rateLimits.primary",
            "usedPercent": "usedPercent", "resetsAt": { "epochSeconds": "resetsAt" },
            "window": { "minutes": "windowDurationMins" } },
          { "name": "Weekly", "at": "$.result.rateLimits.secondary",
            "usedPercent": "usedPercent", "resetsAt": { "epochSeconds": "resetsAt" },
            "window": { "minutes": "windowDurationMins" } },
          { "each": "$.result.rateLimitsByLimitId", "skipKeys": ["codex"],
            "name": { "firstOf": ["limitName", "limitId", "$key"], "dropPrefix": "codex_", "capitalize": true },
            "windows": [ { "at": "primary" }, { "at": "secondary", "suffix": " 7d" } ],
            "usedPercent": "usedPercent", "resetsAt": { "epochSeconds": "resetsAt" },
            "window": { "minutes": "windowDurationMins" } } ] } },
      "fallback": "tty"
    },
    {
      "kind": "api", "label": "API", "summary": "Calls ChatGPT API directly",
      "credential": {
        "jsonFile": { "path": "~/.codex/auth.json",
                      "token": "$.tokens.access_token", "refreshToken": "$.tokens.refresh_token",
                      "account": "$.tokens.account_id", "refreshedAt": "$.last_refresh" },
        "refresh": { "oauth2": { "tokenURL": "https://auth.openai.com/oauth/token",
                                 "clientId": "app_EMoamEEZ73f0CkXaXp7hrann",
                                 "every": "8d", "onStatus": [401],
                                 "expiredCodes": ["refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated"],
                                 "hint": "Run `codex` in terminal to log in again." } } },
      "fetch": { "http": {
        "url": "https://chatgpt.com/backend-api/wham/usage",
        "headers": { "Authorization": "Bearer {{token}}", "ChatGPT-Account-Id": "{{account}}",
                     "Accept": "application/json", "User-Agent": "OpenUsage" } } },
      "mapping": { "json": {
        "plan": "$.plan_type",
        "quotas": [
          { "name": "Session", "at": "$.rate_limit.primary_window",
            "usedPercent": ["$header.x-codex-primary-used-percent", "used_percent"],
            "resetsAt": [ { "epochSeconds": "reset_at" }, { "secondsFromNow": "reset_after_seconds" } ],
            "window": { "seconds": "limit_window_seconds" } },
          { "name": "Weekly", "at": "$.rate_limit.secondary_window", "…": "same shape" },
          { "each": "$.additional_rate_limits[*]",
            "name": { "firstOf": ["limit_name", "metered_feature"], "dropPrefix": "codex_", "capitalize": true },
            "windows": [ { "at": "rate_limit.primary_window" }, { "at": "rate_limit.secondary_window", "suffix": " 7d" } ],
            "…": "same shape" } ],
        "cost": { "kind": "extraUsage", "limit": 1000,
                  "remaining": ["$header.x-codex-credits-balance", "$.credits.balance"] } } }
    },
    {
      "kind": "tty", "label": "Terminal", "hidden": true,
      "fetch": { "terminal": { "cli": "codex", "args": ["-s", "read-only", "-a", "never"], "send": "/status" } },
      "mapping": { "text": { "quotas": [
        { "name": "Session", "pattern": "5h limit[\\s\\S]{0,400}?([0-9]{1,3})% left", "leftPercent": 1 },
        { "name": "Weekly",  "pattern": "Weekly limit[\\s\\S]{0,400}?([0-9]{1,3})% left", "leftPercent": 1 } ] } }
    }
  ]
}
```

What the JSON mapping language must therefore say — each a **feature every
provider gets**, never a Codex special case:

| Feature | Why Codex needs it | Who else will |
|---|---|---|
| `at` · `each` over arrays and maps · `skipKeys` · `$key` | additional limits arrive as an array (API) or a map keyed by limit id (RPC) | any provider with per-model limits |
| `usedPercent` **or** `leftPercent` | Codex reports used | most report used; some left |
| a list = first that answers, including `$header.<name>` | headers are preferred over the body | rate-limit headers are common |
| `resetsAt`: `epochSeconds` · `secondsFromNow` · `iso8601` | both shapes occur | all |
| `window`: `seconds` · `minutes` | the window length is the provider's word ([the law](CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them)) | all |
| name rules: `firstOf`, `dropPrefix`, `capitalize`, `suffix` | `codex_spark` → `Spark`, `Spark 7d` | any provider with model names |
| constants (`"limit": 1000`) | credits have a fixed ceiling | balance providers |

**A rule the language cannot say yet** (today's free-plan defaults in the RPC
client are one) becomes a new mapping feature with its own test, or — if no
second provider could ever use it — is questioned until it goes away. It never
becomes vendor code.

## 4 · The runtime

### 4.1 · The types

```swift
// Providers — the definition: a value, decoded and validated on load
public struct ProviderDefinition: Sendable, Equatable, Codable {
    public let id: String, name: String, cli: String?
    public let links: Links, enabledByDefault: Bool
    public let dataSources: [DataSourceDefinition]   // ≥ 1, unique kinds
    public let defaultDataSource: String             // names one of them
}

// DataSources — the JSON of one data source: no behaviour
public struct DataSourceDefinition: Sendable, Equatable, Codable {
    public let kind: String, label: String, summary: String?, hidden: Bool
    public let credential: CredentialLookup?
    public let fetch: Fetch
    public let mapping: Mapping
    public let fallback: String?
}

// DataSources — three closed sums, one case per JSON tag
public enum CredentialLookup: Sendable, Equatable, Codable {
    case environment(String), setting(String), jsonFile(JSONFileFields),
         keychain(service: String), browserCookie(domain: String)
    indirect case refreshing(CredentialLookup, OAuth2Refresh)
}
public enum Fetch: Sendable, Equatable, Codable {
    case http(HTTPRequest), jsonRpc(JSONRPCCall), cli(CLICall),
         terminal(TerminalSession), file(path: String), script(path: String),
         cloudWatch(CloudWatchQuery)
}
public enum Mapping: Sendable, Equatable, Codable {
    case json(JSONMappingRules), text(TextMappingRules)
}

// DataSources — ONE type that fetches for every provider
public struct DataSource: Sendable {
    public let definition: DataSourceDefinition
    public func fetchUsage() async throws -> UsageSnapshot   // look up → fetch → map
    public func isReady() async -> Bool
}

// DataSources — the factory: the only place a case meets its connection
public enum DataSources {
    public static func make(_ definition: DataSourceDefinition,
                            settings: any ProviderSettingsRepository,
                            vault: any CredentialRepository,
                            cloudWatch: (any CloudWatchClient)? = nil) -> DataSource
}

// Providers — THE lifecycle
@MainActor @Observable
public final class Provider: AIProvider {
    public let definition: ProviderDefinition
    public let dataSources: [DataSource]
    public private(set) var activeKind: String       // persisted
    public var isEnabled: Bool                        // persisted
    public private(set) var isSyncing = false
    public private(set) var snapshot: UsageSnapshot?  // kept on failure
    public private(set) var lastError: Error?
    public func use(_ kind: String) -> Bool
    public func refresh() async throws -> UsageSnapshot   // active, then its fallback
}
```

Inside `DataSource`, `fetchUsage()` switches on the three cases and hands each
to its `internal` worker, built by the factory with **only** the connection
that case needs: `HTTPFetcher` holds a `NetworkClient`, `CLIFetcher` a
`CLIExecutor`, `JSONRPCFetcher` an `RPCTransport` factory, `SettingReader`
the settings, `KeychainReader` the vault. No type receives a bag of
everything.

`AIProvider` stays the protocol the Monitor and views consume while the other
providers move; `Provider` conforms. When the last `XxxProvider` is gone it
folds into `Provider`. `UsageSnapshot` keeps its name until the renames of
slice 7 (`Usage`).

### 4.2 · Flows

**Launch.** `ProviderCatalog` reads the definitions (bundled, then
`~/.claudebar/providers/`, then extensions) → `Providers.make` builds one
`Provider` each, its data sources made live by `DataSources.make` →
`QuotaMonitor` receives them. A file that fails to decode — an unknown tag
included, since the sums are closed — is logged by file name and left out;
the rest load.

**Refresh.** `QuotaMonitor.refresh(id)` → `provider.refresh(kind)` →
`activeDataSource.fetchUsage()` off the main actor: look up the key
(refreshing it when the lookup says so), fetch, map. On failure the provider
tries the active data source's `fallback` once. Success replaces `snapshot`
and clears `lastError`; failure sets `lastError` and **keeps `snapshot`**.

**A 401.** `HTTPFetcher` reports the status; when the lookup is
`refreshing(_, oauth2)` with `onStatus: [401]`, the data source refreshes once
and fetches once more. An `expiredCodes` match becomes
`sessionExpired(hint:)` with the definition's hint.

**Switching data source.** The card writes `<id>.probeMode`, or calls
`provider.use(kind)`; both land on the same key, read on the next refresh.

**Test Connection.** Build a throw-away `Provider` from the unsaved
definition, refresh once, show the usage or the error, write nothing.

## 5 · Settings and secrets

| Key | Means | Status |
|---|---|---|
| `providers.<id>.isEnabled` | the Providers pane toggle | unchanged |
| `<id>.probeMode` | the active data source's `kind` | unchanged — a match name, so no user's setting moves |
| `providers.<id>.settings.<field>` | a non-secret form value | new |
| vault `claudebar.<id>.<field>` | a secret form value | new; Keychain with the file fallback Notify! uses for ad-hoc builds |

A credential lookup never writes settings, with one exception the definition
asks for by name: `OAuth2Refresher` writes the refreshed token **back to where
the credential came from** (for Codex, `~/.codex/auth.json`, preserving every
other field), because the CLI that owns that file must keep working.

## 6 · Concurrency, errors, logging

- `Provider` is `@MainActor @Observable`; `DataSource` and its workers are
  `Sendable` and `nonisolated`, so CLI, RPC and HTTP work runs off the main actor.
- At most one refresh per provider is in flight; a second call waits for the
  first one's result.
- `DefinitionError` (bad JSON, unknown tag, missing default, duplicate kind)
  is a load-time error with the file name. It never crashes the app.
- Workers log what they did (`AppLog.probes`), never what they carried: no
  token, header value, `{{secret}}` substitution, or response body at `info`
  or above. A response body is logged at `debug` only by the mapper,
  truncated, and only when mapping fails.

## 7 · Testing

| Subject | Test | How |
|---|---|---|
| each worker | its protocol or format, alone | `@testable`, built with a mocked connection (`NetworkClient`, `CLIExecutor`, `RPCTransport`); Chicago: assert on the payload / snapshot |
| `JSONMapper` · `TextMapper` | every mapping feature | small JSON/text fixtures, one feature per test |
| `DataSource` | look up → fetch → map, 401-refresh-retry, errors | built with mocked connections |
| `Provider` | lifecycle: keeps usage on failure, fallback, `use`, enabled persists | data sources over mocked connections |
| each definition | **golden test**: today's recorded responses (`Tests/…/Fixtures/codex/`) through the definition produce exactly the snapshot today's probe produced | the fixtures are captured from the current probe tests before the probe is deleted |
| the catalog | every bundled definition decodes | one test over `Resources/Providers/*.json` |

The golden tests are how deleting `CodexUsageProbe` stays safe: the JSON must
reproduce its output, quota for quota, before the Swift goes.

## 8 · Migration slices

Each slice is one PR, green, with no change a user can see unless it says so.

| # | Slice | Done when |
|---|---|---|
| **1** | **Codex** — the definition types, `CredentialLookup` · `Fetch` · `Mapping`, `DataSource`, `Provider`; workers `JSONFileReader`, `OAuth2Refresher`, `HTTPFetcher`, `JSONRPCFetcher`, `TerminalFetcher`, `JSONMapper`, `TextMapper`; `codex.json`; golden tests | `CodexProvider`, `CodexUsageProbe`, `CodexAPIUsageProbe`, `DefaultCodexRPCClient`, `CodexCredentialLoader` are deleted; both modes and the fallback work; `codex.probeMode` is read as before |
| 2 | the HTTP + API-key providers (DeepSeek, MiniMax, Z.ai, Kimi API, Vercel, …): `EnvironmentReader`, `SettingReader` | their probes and provider classes are deleted |
| 3 | the look and the settings form move into the JSON; the `switch id` tables and the simple config cards go | adding a provider edits no Swift |
| 4 | the kernel laws: `Left` (no fake 100%), `Window` (no guessed length) | balance definitions map money only |
| 5 | the CLI and cookie providers (Gemini, Kiro, Cursor, AmpCode, Antigravity, Alibaba, …): `CLIFetcher`, `BrowserCookieReader`, …; Bedrock via `Fetch.cloudWatch` and the `AWSClients` module; extensions read as definitions; *PROBE MODE* → *DATA SOURCE* | no `XxxUsageProbe` is left |
| 6 | *Add Provider*: the sheet, Test Connection, Save | a user adds a provider without a restart |
| 7 | Claude (PTY CLI, multi-account, guest passes, budget); the renames (`Usage`, `Plan`, `Cost`, `DataSourceError`) | `AIProvider` folds into `Provider` |

## 9 · Open

- **The mapping language's ceiling.** Slices 1, 2 and 5 will find what it must
  express. If a provider needs real computation (Bedrock prices tokens per
  model), that is a fetch case's job — `Fetch.cloudWatch` returns usage
  already priced — not a scripting language inside the mapping.
- **JSONPath dialect.** A small, documented subset (`$.a.b`, `[*]`, maps by
  key, `$header.`), implemented and tested here, rather than a dependency.
- **Multi-account in a definition.** Claude has accounts today; slice 7
  decides whether a definition declares them or a credential lookup discovers
  them.
- **A `command` fetch from the UI** — see [CANONICAL_MODEL §9](CANONICAL_MODEL.md#9--open).
