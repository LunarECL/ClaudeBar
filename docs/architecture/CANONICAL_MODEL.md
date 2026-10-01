---
description: THE normative tree ClaudeBar binds to — every node from the Monitor down, the word the screen prints for it, its laws and their owners, the bounded contexts and the modules that implement them; read before adding or changing any domain type or provider.
---

# ClaudeBar — the canonical model

> ONE tree. The menu bar, the popover, the Settings window, the notch, the
> Touch Bar and Notify! all read it; none of them adds a rule to it. A node is
> here because a user can point at it on screen, and a rule lives on **the node
> that holds the data it needs** (tell, don't ask).
>
> **Status: PROPOSED — design, not build truth.** Written 2026-10-01 from the
> code as it stands (`Sources/Domain`, 20 providers, the extension system) and
> from the words the interface prints. Where the code and this tree disagree,
> §8 says which way the code moves. Nothing here has been migrated yet.
>
> | Question | Document |
> |---|---|
> | *What is the tree, node by node, and who owns which law?* | **this one** |
> | *Which module, which file, which order?* | [TARGET_ARCHITECTURE.md](TARGET_ARCHITECTURE.md) |
> | *How are the layers and data flow wired today?* | [ARCHITECTURE.md](ARCHITECTURE.md) |
> | *Who uses it, and what do the new screens say?* | [USER_JOURNEYS.md](USER_JOURNEYS.md) — the outside-in walk this tree was revised against |
> | *What does a user DO with the app today?* | [USER_BEHAVIORS.md](USER_BEHAVIORS.md) |
> | *How does one provider fetch its data?* | `docs/providers/<id>/design.md` |

---

## 0 · How to read it

| Mark | Means |
|---|---|
| **◆** | a domain object with commands and laws — it can say no |
| **◇** | a value — it answers, and cannot be told anything |
| **DERIVED** | computed from other nodes, never stored |

**The words are the ones the screen prints.** A name is harvested from the
interface, never from backstage jargon; when the interface has no word yet,
the industry's is taken. The screen prints *Providers*, *All Providers*,
*Accounts*, *Add Account*, *PROBE MODE* (subtitled *Data fetching method*),
*CLI Mode · API Mode · RPC Mode*, *Save & Test Connection*,
*Fetching usage data…*, *No usage data*, *Updated 3m ago*, *Session · Weekly*,
*Low quota*, *each quota window resets*, *% left*, *remaining*, *Resets in 2h 5m*,
*Balance*, *Credits*, *API COST*, *EXTRA USAGE*, *Daily Budget*, *Claude Max
plans*, *HEALTHY · WARNING*, *On track · Running hot · Room to spare*, *TODAY'S
USAGE*. The screens the redesign adds — walked first in
[USER_JOURNEYS.md](USER_JOURNEYS.md) — print *Add Provider*, *Start from: API ·
CLI · File · Copy a provider*, *Key lookup order*, *Test Connection*,
*Response*, *Map fields: Used · Remaining · Limit · Resets*, *Built in ·
Custom · Extension*, *Export*, *Import*, *Couldn't read your key · Couldn't
connect · Couldn't find the numbers*, *via API*. Those are the words below.

### 0.1 · Words the code uses, and ours

| The code's word | Ours | Why ours |
|---|---|---|
| `AIProvider` | **`Provider`** | the screen prints *Providers*. The `AI` prefix tells the reader nothing; every provider is one |
| `UsageProbe`, and every `XxxUsageProbe` (find the credential, refresh it, fetch, fall back AND parse — in one vendor-named type) | **`DataSource`** — a **`DataSourceDefinition`** (`CredentialLookup` + `Fetch` + `Mapping`, plain data) made live with exactly the one connection its fetch needs; it fetches its own usage | the screen has to translate its own header: *PROBE MODE* is subtitled *Data fetching method*, and everywhere else it says *Fetching usage data…* and *Test Connection*. Settings screens that do this job — Grafana, Metabase, Retool — call it a **data source** and test it with *Save & test*. And it is two questions — *how do I get the bytes?* and *what do they say?* — which a user building a provider in the UI answers on two different steps; a third, *whose key?*, the screen already prints as *TOKEN LOOKUP ORDER* · *API KEY LOOKUP ORDER* · *COOKIE SOURCE*. *Probe* is the industry's word for checking something is alive (a Kubernetes liveness probe), which is our `healthCheck`, not this |
| the *PROBE MODE* header | **DATA SOURCE**, choices *CLI · API · RPC* | the subtitle goes; it no longer translates anything. The saved setting key and the extension manifest's `"probe"` key and `probe.sh` stay — keys are match names, labels are display names |
| `ProbeError` | **`DataSourceError`** | the failure of a data source — what *Save & Test Connection* reports when the connection is not verified |
| `UsageSnapshot` | **`Usage`** | the screen prints *Fetching usage data…* · *No usage data* · *Updated 3m ago*, and the vendors' own command is `/usage` (we run `claude /usage`). It is the provider's usage, as of when it was updated. *Snapshot* is the code's word for any frozen value |
| `capturedAt` | **`updatedAt`** | the screen prints *Updated 3m ago* |
| `UsageQuota` | **`Quota`** | the product's own word — *"shows AI coding quotas"* |
| `percentRemaining` + `dollarRemaining` + `dollarCap` (+ `percentRemaining: 100` as a placeholder) | **`Quota.left: Left`** — `share(Percent)` · `money(Money, of: Money?)` | the screen prints *% left* OR *$12.40 remaining*. Never both, and a balance with no ceiling has no percentage |
| `QuotaType` (name **and** a guessed duration) | **`Quota.name`** + **`Quota.window: Window?`** | *Session* is what it's called; *5 hours, resets 11am* is when it refills. The code derives the second from the first |
| `QuotaStatus` | **`Status`** | prints HEALTHY · WARNING · CRITICAL · DEPLETED |
| `UsagePace` | **`Pace`** | prints On track · Running hot · Room to spare |
| `CostUsage` | **`Cost`**, of a kind: `api` · `extraUsage` | the card prints *API COST* or *EXTRA USAGE* — two kinds of money gone, one shape |
| `BudgetStatus` + the API budget setting | **`Budget`** | prints *Daily Budget*, *Claude API Budget* — and ON TRACK · NEAR LIMIT · OVER BUDGET |
| `AccountTier` (`.claudeMax`, `.claudePro`, …) | **`Plan`** | the badge prints MAX · PRO · API; vendors call it a *plan* (Claude Max plan, Coding Plan). A vendor's name does not belong in the shared kernel |
| `ConfigField` (extensions only) | **`Setting`**, in a **`SettingsForm`** | prints *API KEY*, *REGION*, *SETTINGS.JSON PATH*. Every provider's config card is one of these forms |
| `ExtensionManifest` | **`ProviderDefinition`** | the same thing a user makes with *Add Provider*, read from disk instead of a form |

> **One word, two fences.** *Session* means the 5-hour quota window inside
> **Quota**, and a running Claude Code process inside **Activity**. Both are on
> screen and both stay; the fence (§7) is what keeps them from meeting.

## 1 · The tree

```text
Monitor  ◆                                  THE ROOT — what the menu bar is watching. One per app
├── providers: [Provider]                   the Providers pane's order
├── lineup → [Account]                      DERIVED — the enabled accounts of the enabled providers,
│                                           in that order: the pills, the menu bar, the notifications
├── selection: Account.ID                   which pill the popover opens on — `codex` · `codex.<acct>`
│   │
│   └── Provider  ◆                         THE PRODUCT — HOW TO FIND OUT, once for all its logins.
│       │                                   Built in, made by the user, or an extension
│       ├── profile: ProviderProfile  ◇     WHO IT IS — the only place an id becomes a face
│       │   ├── id: ProviderID              stable forever; settings are keyed by it
│       │   ├── name                        "DeepSeek"
│       │   ├── look: ProviderLook          symbol · colour · gradient — data, never a switch on id
│       │   ├── links                       dashboard · status page · "Open DeepSeek API Keys"
│       │   └── origin                      builtIn · custom · extension — "Built in · Custom · Extension"
│       ├── isEnabled                       the pane's toggle — off hides every login
│       ├── settingsForm: SettingsForm  ◇   WHAT IT NEEDS FROM YOU — [Setting]: API KEY, REGION, ENV
│       │                                   VAR … each says its kind (text · secret · number ·
│       │                                   toggle · choice · path), its default, and its SCOPE:
│       │                                   provider (REGION, ENV VAR NAME) or account (the Codex
│       │                                   folder, an API key) — "Add Account" fills the account
│       │                                   scope. A SECRET is a reference into the vault, never a value
│       ├── dataSource: kind                the one in use — one choice for every login ("DATA SOURCE")
│       ├── dataSources: [DataSource]  ◆    HOW WE FIND OUT — one or more; "DATA SOURCE" picks one
│       │   └── DataSource  ◆               ONE TYPE FOR EVERY PROVIDER — its definition, made live by
│       │       │                           the factory with only the connection its fetch needs
│       │       ├── definition: DataSourceDefinition  ◇   THE JSON — no behaviour:
│       │       │   ├── kind                CLI · API · RPC · Script · HTTP · File — the choices
│       │       │   ├── credential: CredentialLookup?   WHOSE KEY — "TOKEN LOOKUP ORDER": the first
│       │       │   │                       that answers of environment(var) · setting(field) ·
│       │       │   │                       jsonFile(path, fields) · keychain(service) ·
│       │       │   │                       browserCookie(domain) — and how it stays fresh:
│       │       │   │                       refresh: oauth2(tokenURL, clientId, every, on 401)
│       │       │   ├── fetch: Fetch        HOW TO GET THE BYTES — "Data fetching method". A closed sum:
│       │       │   │                       http(request) · jsonRpc(cli, handshake, call) · cli(args) ·
│       │       │   │                       terminal(cli, keys) · file(path) · script(path)
│       │       │   ├── mapping: Mapping    WHAT THE BYTES SAY — a closed sum:
│       │       │   │                       json(paths, each, used|left, resets) · text(patterns) ·
│       │       │   │                       script(file) — JavaScript in JavaScriptCore, no I/O,
│       │       │   │                       for a format no rule can say (a TUI screen)
│       │       │   └── fallback: kind?     the data source to try when this one fails — Codex's
│       │       │                           RPC falls back to its terminal
│       │       ├── fetchResponse(for: Account) → Response   "Test Connection" — looks up the key and fetches;
│       │       │                           stops BEFORE mapping, so a person with nothing mapped
│       │       │                           yet can see what came back
│       │       ├── fetchUsage(for: Account) → Usage   "Fetching usage data…" — mapping.read(fetchResponse())
│       │       └── isReady(for: Account)   DERIVED — the key answers and the CLI exists ("Configured")
│       │                                   The ACCOUNT's values fill `{{account.x}}` when the fetch
│       │                                   runs, as the token fills `{{token}}` — one definition,
│       │                                   never a copy per login
│       ├── accounts: [Account]  ◆          NEVER EMPTY. One account is the "default" — the plain login
│       │   └── Account  ◆                  A LOGIN YOU PAY FOR — who, and what we last saw. No behaviour
│       │       ├── id: Account.ID          `<provider>` for the default, `<provider>.<acct>` for an added one
│       │       ├── label · email           what you gave, or the login file holds — names the pill
│       │       ├── values                  its account-scope settings — the Codex folder, the login's
│       │       │                           account id; a secret as a reference
│       │       ├── isEnabled               PAUSE without forgetting — no refresh, no pill. "Remove" forgets
│       │       ├── usage: Usage?  ◇        WHAT WE LAST SAW — survives a failed refresh; carries the
│       │       │                           plan and organization the data source learned
│       │       ├── sync: SyncState  ◇      FETCH HEALTH — isSyncing · lastError: DataSourceError. Never
│       │       │                           erases the usage. The error names its STEP — lookup · fetch ·
│       │       │                           mapping — "Couldn't read your key · Couldn't connect ·
│       │       │                           Couldn't find the numbers" — because each sends you somewhere else
│       │       ├── budget: Budget?  ◇      THE USER'S OWN CEILING on this login's Cost — a Daily
│       │       │                           Budget, the Claude API Budget. The vendor sets quotas;
│       │       │                           the user sets budgets. Set in the provider's form
│       │       │                           (account scope), since one login's API spend is not another's
│       │       └── status                  DERIVED — QUOTA HEALTH: the worst quota in its usage.
│       │                                   The pill's and the menu-bar entry's colour
│       ├── status                          DERIVED — the worst across its enabled accounts
│       └── bestAccount                     DERIVED — the enabled account with the most left: "switch to work"
│
└── statusPolicy: StatusPolicy  ◇           HOW STRICT TO BE — absolute thresholds, or pace-aware
                                            with the user's burn-rate threshold. ONE for the app
                                            (General): every surface — menu bar, pill, card, Touch
                                            Bar, notch, notifications, status export — reads the
                                            same status. Colours are not policy: they are the page's

Usage  ◇                                    "Fetching usage data…" — WHAT THE PROVIDER SAYS, AS OF A MOMENT
├── updatedAt                               "Updated 3m ago"; stale after 5 minutes
├── source: kind                            "via RPC" · "via Terminal" — which data source answered,
│                                           so a fallback is never silent
├── quotas: [Quota]
│   └── Quota  ◇                            ONE LIMIT THE VENDOR SET
│       ├── name                            Session · Weekly · Opus · Monthly · Balance · Credits
│       ├── group?                          the card section, when one provider spans several
│       │                                   upstream accounts ("Claude · work")
│       ├── left: Left                      A CLOSED SUM OF TWO:
│       │                                     share(Percent)            "62% left"
│       │                                     money(Money, of: Money?)  "$12.40 remaining", "of $50"
│       ├── window: Window?                 WHEN IT REFILLS — length + resetsAt. "Resets in 2h 5m".
│       │                                   A prepaid balance has none
│       ├── status                          DERIVED — Left × StatusPolicy (× Window, when pace-aware)
│       └── pace                            DERIVED — needs a Window; otherwise unknown
├── cost: Cost?  ◇                          MONEY GONE — "API COST" or "EXTRA USAGE", over a period.
│                                           Judged by a Budget, never by a Quota
└── account facts                           email · organization · plan, when the data source learns them —
                                            the screen prefers these to what the Account was given

Response  ◇                                 "Response" — WHAT CAME BACK, before anyone read it:
                                            status · headers · body. The Map fields step shows it

    DELIBERATELY OUTSIDE THE MONITOR
Activity  ◆                                 Claude Code sessions seen through hooks — the notch
UsageHistory  ◆                             "TODAY'S USAGE" — read from local logs, not a meter
Destinations                                notifications · Notify! · live activity · status export

    NOT IN THE MODEL (the page's)
MenuBarLabel · display mode (left/used) · countdown colon · popover height · theme ·
provider pills · card titles shortened for width
```

## 2 · A provider is DATA; one DataSource type fetches for all of them

The user's sentence is the design: *a provider only needs to know how to fetch
the data and how to read the usage.* "Knows how" is a DEFINITION, not a class.
Everything else a provider has today — the syncing flag, the last error, the
enabled toggle, the account switch, the settings plumbing, the icon — is the
same for all of them, so it is written once and a provider does not get a say.

Take Codex. Its two probes do five jobs between them, and **not one of them is
Codex logic**:

| The job | What `CodexAPIUsageProbe` / `CodexUsageProbe` hard-code | What it really is |
|---|---|---|
| whose key | read `~/.codex/auth.json` → `tokens.access_token`, `tokens.account_id` | `credential: jsonFile(path, fields)` |
| keep it fresh | refresh-token grant to `auth.openai.com/oauth/token` after 8 days or on 401, write it back | `refresh: oauth2(tokenURL, clientId, every: 8d, on: 401)` |
| get the bytes | `GET chatgpt.com/backend-api/wham/usage` with three headers · or spawn `codex app-server`, JSON-RPC `initialize` → `initialized` → `account/rateLimits/read` | `fetch: http(…)` · `fetch: jsonRpc(…)` |
| when that fails | scrape the terminal for `5h limit … 62% left` | `fallback` to a `terminal` fetch + `text` mapping |
| what it says | `used_percent` → left, `reset_at` / `reset_after_seconds` → resets, `additional_rate_limits[]` → more quotas, `codex_` prefix dropped | `mapping: json(…)` |

So every provider is ONE KIND OF THING — a definition — and ONE `DataSource`
type does the fetching for all of them: `dataSource.fetchUsage()` looks up
the key, fetches, maps. Behind it, each CASE of the three closed sums is
carried out by one internal worker with one job, named for its protocol or
format, never for a vendor:

| Closed sum | Its cases' workers (`internal`) |
|---|---|
| `CredentialLookup` | `EnvironmentReader` · `SettingReader` · `JSONFileReader` · `KeychainReader` · `BrowserCookieReader` · `OAuth2Refresher` |
| `Fetch` | `HTTPFetcher` · `JSONRPCFetcher` · `CLIFetcher` · `TerminalFetcher` · `FileFetcher` · `ScriptFetcher` |
| `Mapping` | `JSONMapper` · `TextMapper` · `ScriptMapper` (JavaScriptCore; host `humanDate()`) |

**Why closed sums.** The JSON decoder must know every tag, and the *Add
Provider* sheet offers a fixed list. A new provider is a JSON file — open, no
Swift. A new protocol (say gRPC) is a new case and one new worker: a
deliberate change to a closed list, which is honest, because a new picker
option, decoder tag and form come with it anyway.

**When a vendor really is different** — Bedrock reads AWS CloudWatch through
the AWS SDK; another signs its requests with its own scheme — the difference
is still ONE job, so it is still one case with one worker named for the
technology or the scheme (`Fetch.cloudWatch`, a signature case named for its
algorithm), taking its parameters from the JSON. There is never a type that
does all five jobs for one vendor.

| Origin — the badge the screen prints | Definition lives in | Made by |
|---|---|---|
| **Built in** | `Resources/Providers/<id>.json`, shipped in the app | us |
| **Custom** | `~/.claudebar/providers/<id>.json` | the person, in *Add Provider*, *Copy a provider* or *Import* |
| **Extension** | `~/.claudebar/extensions/<id>/manifest.json` — a `script` fetch | the person, by hand |

The three differ only in *where the file is*. Codex, DeepSeek and a provider
someone made five minutes ago run on the same `DataSource` and the same lifecycle.

## 3 · The commands, and the node each lands on

| The user does | The node is told | Notes |
|---|---|---|
| toggles a provider in Providers | `provider.enable()` · `disable()` | every login of it; the pane keeps its place |
| toggles one account | `account.enable()` · `disable()` | pauses that login — no refresh, no pill — and keeps its settings |
| drags the pane's order | `monitor.providers.move(_:to:)` | the lineup follows |
| picks DATA SOURCE | `provider.use(_ kind:)` | one data source active at a time |
| fills API KEY, REGION … | `provider.settings.set(_:to:)` | a secret goes to the vault; the form keeps the reference |
| *Add Account* · *Remove* | `provider.add(account:)` — fills the form's account scope · `provider.remove(account:)` | never removes the default; removing forgets the account's settings, never its CLI's login files |
| clicks a pill | `monitor.select(_ account:)` | |
| refreshes | `monitor.refresh(_:kind:)` → `provider.refresh(account, kind)` | interactive or background; one account's fetch |
| *Add Provider* → *Start from* | `ProviderDefinition.blank(fetch:)` · `definition.copy()` | the picker is `http` · `cli` · `file`; a copy gets a new id and the origin **custom** |
| *Connect* → *Test Connection* | `dataSource.fetchResponse(for: account)` → a `Response` or a `DataSourceError` | nothing is mapped yet, nothing is saved |
| *Map fields* — clicks a value | `mapping.quotas.append(…)` / `mapping.cost = …` with *Used · Remaining · Limit · Resets* | the card previews live from the same `Response` |
| *Save* | `catalog.add(definition)` → `monitor.lineup.append` | no restart |
| *Edit* · *Delete* a custom provider | `catalog.replace(definition)` · `catalog.remove(id)` | built-ins can only be disabled |
| *Export…* | `definition.exported()` → a `.json` file | carries the lookup order and the setting names — never a key |
| *Import provider* | `catalog.import(file)` → `definition.missingSettings` | says where a key will be sent, and shows a CLI command, BEFORE asking |
| sets a Daily Budget · the Claude API Budget | `account.budget = …` (an account-scope setting) | judges that login's cost only |
| turns the burn-rate warning on, sets its threshold | `monitor.statusPolicy = …` | every status and every alert follows at once |
| chooses status colours · high contrast | — the page's theme | how a status looks, never what it is |

## 4 · The reads — what the tree answers

```text
monitor.overallStatus                → Status       the menu bar's colour: the worst
monitor.lowestQuota                  → Quota?       across the lineup (enabled accounts of enabled providers)
monitor.lineup                       → [Account]    the pills and the menu-bar entries
account.usage                        → Usage?       that login's latest — what its pill shows
account.status                       → Status       QUOTA HEALTH: the worst quota in that usage
account.sync.lastError               → DataSourceError?  FETCH HEALTH: which step failed — never a Status
provider.status                      → Status       the worst across its enabled accounts
provider.bestAccount                 → Account?     the most left — "switch to work"
usage.quota(named:)                  → Quota?
usage.isStale                        → Bool         older than 5 minutes
quota.status(under: StatusPolicy)    → Status
quota.pace                           → Pace         unknown without a window
quota.window?.timeUntilReset         → Duration?    "Resets in 2h 5m"
account.budgetStatus                 → BudgetStatus? ON TRACK · NEAR LIMIT · OVER BUDGET —
                                                    usage.cost judged by account.budget
dataSource.fetchResponse(for:)       → Response     Test Connection: what came back, unmapped
mapping.read(response)               → Usage        Map fields: the live card
definition.missingSettings           → [Setting]    Import: "Key needed"
```

## 5 · The laws, on the node that owns them

| Law | Owner |
|---|---|
| a provider's id is stable forever; settings, the menu-bar choice and the lineup are keyed by it. A custom provider's id is minted once and never derived from its name | `ProviderProfile` |
| a provider's face is DATA — its symbol and colours ride on the profile, so adding one never edits a `switch id` | `ProviderLook` |
| a provider has at least one account; the `default` account's id equals the provider id, an added one's is `<provider>.<acct>` — the ids today's settings and menu-bar pins are keyed by | `Provider.accounts` |
| a provider is the PRODUCT and an account a LOGIN: how to fetch, the data source choice, the look and the provider-scope settings are the provider's, once; who, its values, what we saw and whether the last fetch worked are the account's | `Provider` · `Account` |
| accounts are SIMULTANEOUS — every enabled login is fetched and shown as its own pill; the popover shows the selected one. (A vendor that allows one live login at a time would add an `active` account; none does today) | `Monitor.selection` |
| one definition serves every account: the account's values fill `{{account.x}}` when the fetch runs; a data source is never copied per login | `DataSource` |
| status is QUOTA health, derived from usage; a failed fetch is FETCH health, in `sync` — a key that expired never turns the menu bar red | `Account.status` · `Account.sync` |
| a disabled account is paused, not forgotten; a provider whose accounts are all disabled reads as disabled | `Account.isEnabled` |
| a failed refresh keeps the last usage and records the error beside it — what we saw is never erased by failing to look again | `Account.sync` |
| at most one refresh per account is in flight | `Provider` |
| exactly one data source is active per provider; switching never loses settings the other one needs | `Provider.dataSources` |
| a data source reads settings only through its form; it never writes settings and never reads another provider's | `DataSource` · `SettingsForm` |
| a secret never appears in `settings.json`, a log line, an error message or a test fixture — the form holds a reference, the vault the value, and the vault falls back when the Keychain refuses an ad-hoc build | `Setting` · `SecretVault` |
| **`left` is ONE OF TWO**: a share, or money. A balance with no ceiling has NO percentage — writing 100% is a lie the status then believes | `Quota.left` |
| money keeps its currency; two currencies are never added or compared | `Money` |
| **a window's length is the provider's word**, never guessed from a quota's name — the Codex RPC's primary window can be the weekly one | `Window` |
| pace exists only inside a window with a reset; outside it is `unknown`, never `onPace` | `Quota.pace` |
| depleted at 0, critical under 20 — ABSOLUTE, whatever the policy; pace-aware only decides WARNING vs HEALTHY between 20% and 50% left | `StatusPolicy` |
| ONE status per quota: the menu bar, the cards, the Touch Bar, the notch, the status export and the notifications all read `quota.status(under: monitor.statusPolicy)` — never their own copy of the rule | `StatusPolicy` · `Monitor` |
| a quota is the vendor's ceiling; a budget is the user's. A Cost is judged by a Budget, never shown as a Quota. A budget judges ONE account's cost — two logins' spend is never summed against it | `Cost` · `Account.budget` |
| usage is stale 5 minutes after it was updated | `Usage` |
| a background refresh is never faster than the slowest provider's floor, and slower on battery | `Monitor` |
| a data source's definition is DATA; the code behind it is one worker per case, with ONE job, named for a protocol or format — never a vendor | `DataSource` |
| a data source is handed only the connection its fetch needs — an HTTP fetch never holds a CLI | `DataSources` (the factory) |
| a new provider is never a code change; a new protocol or format is one new case and one worker | `Fetch` · `Mapping` · `CredentialLookup` |
| a credential is looked up in the order the definition gives; the first that answers wins, and a refreshed token is written back where it was found | `CredentialLookup` |
| when the active data source fails, its `fallback` is tried once; what the popover shows says which one answered | `Provider` |
| a definition is valid before it is saved: a fetch, a mapping that produced at least one quota or a cost on Test, and every required setting filled | `ProviderDefinition` |
| a built-in provider can be disabled but not deleted; a custom one can be both; an extension is removed by removing its folder | `ProviderCatalog` |
| **an exported definition carries no secret** — the lookup order and each setting's name, never its value | `ProviderDefinition` |
| an import says where a key will be sent, and shows any CLI command it will run, before it asks for a key or saves | `ProviderCatalog.import` |
| an error names the step that failed — lookup, fetch or mapping — and never carries the secret or the response body | `DataSourceError` |
| a usage says which data source produced it; a fallback is never silent | `Usage.source` |

## 6 · What is deliberately NOT in the tree

| Absent | Why |
|---|---|
| `UsageProbe`, and every `XxxUsageProbe` | one vendor-named type doing five jobs — the SRP violation this model exists to remove. Its jobs are three closed sums in a definition, and one `DataSource` that carries them out |
| a module, folder or type per vendor | a vendor is a JSON file. Vendor knowledge is DATA: URLs, paths, field names, client ids |
| a `XxxProvider` class per vendor | the lifecycle is identical in all twenty; only the fetch and mapping differ. Claude's CLI and API modes are two data sources, not a subclass |
| a `XxxSettingsRepository` protocol per vendor | a vendor's settings are a `SettingsForm`; storage is one repository keyed by provider and setting id. ISP is kept by handing each data source ONLY its own form |
| `bedrockUsage` on the usage | a vendor's type in the shared kernel. Bedrock's per-model cost is a `Cost` with lines, or a group of quotas |
| `.claudeMax` · `.claudePro` on `Plan` | a vendor's words in the kernel. A plan is a badge and a name; whether it can issue guest passes is a fact the definition states about that plan |
| `menuBarTitle` · `compactTitle` · `formattedDollar…` · `paceTickHelp` on `Quota` | the page's. A quota does not know how wide the menu bar is |
| `menuBarLabel(…)` on the `Monitor` | the page's. The monitor answers *what is true*; the menu bar decides how to print it |
| `percentRemaining: 100` as "no percentage" | see the law on `Quota.left` |
| `QuotaType.duration` guessing 7 days for a model quota or 30 for "Monthly" | see the law on `Window` |
| a ViewModel or AppState | unchanged: views read the tree |
| Claude Code sessions in the Monitor | a different question with a different *Session* — Activity's |

## 7 · The contexts, and the modules that implement them

Each is a **fence**: inside it every word has one meaning and one model
enforces it. Across a fence the same word may mean something else, as long as
**no type crosses** — a reference does.

| Context | Subdomain | Owns the question | Module |
|---|---|---|---|
| **Quota** | **shared kernel** | *how much is left, when does it refill, and is that OK?* | `Modules/Quotas` |
| **Providers** | **core** | *who do I pay, under which accounts, and what did they last say?* | `Modules/Providers` |
| **Data Sources** | supporting | *how do we find out?* — DataSource, DataSourceDefinition, CredentialLookup, Fetch, Mapping, Setting, DataSourceError, and every worker | `Modules/DataSources` |
| **Monitoring** | **core · conductor** | *what is true right now, and when do we look again?* | `Modules/Monitoring` |
| **Alerting** | generic | *who needs to hear that it changed?* — notifications, Notify!, live activity, status export | `Modules/Alerting` |
| **Activity** | supporting | *what is Claude Code doing right now?* — hooks, sessions, the notch | `Modules/Activity` |
| **Usage History** | supporting | *what did I use today, against yesterday?* | `Modules/UsageHistory` |
| **Vault & Settings** | generic | *where is it kept?* — `settings.json`, secrets | `Modules/Storage` |
| SDK clients | — (anti-corruption layers) | *what does this SDK say?* — a client that needs a heavy SDK gets its own module, behind a port, so only it links the SDK | `Modules/AWSClients` |

```text
                      Quota                    the shared kernel — knows nobody
                    ▲   ▲   ▲
          ┌─────────┘   │   └──────────┐
    DataSources     UsageHistory    Alerting ◀──┐
          ▲                                     │
          │                                     │
          │◀── AWSClients (the SDK)               │
          │                                     │
    Providers ◀──────────── Monitoring ─────────┘        Activity
          ▲                      ▲                      (on its own:
          │                      │                       no Quota, no Provider)
          └──────── App ─────────┘
          the composition root: hands the SDK clients in,
          loads the definitions (built-in JSON ships here), draws the tree
```

Arrows point at the **supplier**. Nothing points back: the kernel cannot name a
provider, Data Sources cannot name the Monitor, no module names a vendor, and
the AWS SDK links into `AWSClients` and nowhere else.

**Packaging.** One Tuist framework target per context under `Modules/`, each
with `Sources/` and `Tests/`. The `**` globs keep working per module; a context's tests link only that
context and what it depends on, so `QuotaTests` stop linking six AWS SDKs.

## 8 · Build truth, node by node

| Node | Today | Moves to |
|---|---|---|
| `Provider` lifecycle | copied into 20 `XxxProvider` classes (`isSyncing`, `snapshot`, `lastError`, `isEnabled`, `refresh`) | one `Provider` in `Providers`; built-ins become JSON definitions |
| `Provider.accounts` · `Account` | **built** (#356): one `Provider` per product owns `[Account]`; an added login runs the same data sources with `accounts.patch` (RFC 7396) merged in and its values filling `{{account.x}}` — bound once per login, so each keeps its own cache and rate-limit memory. `Account` conforms to `AIProvider` as a shim, so the monitor and the pills are untouched; `provider.add` / `remove`, `status`, `bestAccount`. Ids, pills and settings keys unchanged | the shim goes when `AIProvider` folds into `Provider`; `Provider.isEnabled` (hide every login) arrives with the one Codex row (#352) |
| `ExtensionProvider` | a generic provider over scripted sections | the same `Provider`, with `script` fetches — the proof that one lifecycle fits |
| `ProviderProfile` · `look` | **built** (#353) for definition-driven providers: `profile { id, name, links, look, origin }` in the JSON, `look` as plain RGB data; `Account` and the id-only lookups read it, `origin` is set by whoever loads the file. The `switch id` tables (`ProviderVisualIdentity`, `ProviderIcons`, `NotificationAlerter`) keep only the legacy providers; `Theme.swift`'s unused copy is deleted | the tables empty as #331 lands |
| `SettingsForm` | **started** (#352): Claude's and Codex's PROBE MODE cards are one generic *Data source* section read from the definition (choices, key lookup order, fallback sentence and switch, cache note, *Test Connection*); a provider's own inputs (REGION, API KEY, ENV VAR) are not a form yet. Before: 11 settings sub-protocols in `ProviderSettingsRepository.swift`, mirrored in two repositories and 11 config cards; extensions already use `ConfigField` | `ConfigField` generalised; one form renderer; custom cards only where a form cannot say it (Claude's account management) |
| `DataSource` (+ `DataSourceDefinition` = `CredentialLookup` + `Fetch` + `Mapping`) | ~30 vendor-named probes, clients and credential loaders, each doing several jobs | one definition per data source in JSON, one `DataSource` type and ~15 internal workers; every `XxxUsageProbe` is deleted |
| `Quota.left` | **built** (slice 4): `Left` = `share` · `money(Money, of: Money?)` on every `UsageQuota`; status, pace, the lowest quota and the menu bar follow it, so a balance shows its money and has no pace. Legacy probes still write `100` + `dollarRemaining`, which reads as a balance; a JSON mapping writes `left: { money, of }` | `percentRemaining` leaves the call sites as providers migrate |
| `Window` | **built** (slice 4): the kernel no longer guesses — pace uses only a stated `window.length`. Legacy probes state what the guess used to give (`conventionalWindow`, named as a convention; Bedrock's daily budget now 1 day; Cursor's monthly card none, as it chose); Claude's script and JSON and Codex's JSON state their windows, the response's word first | the conventions become each definition's word as providers migrate |
| `Usage` | `UsageSnapshot` with `bedrockUsage`, `extensionMetrics`, `dailyUsageReport` | kernel fields only; the rest moves to their contexts |
| `Plan` | `AccountTier` with Claude cases | a name and a badge |
| `StatusPolicy` | **built** (#357): `StatusPolicy` in `Quotas` with `quota.status(under:)` / `usage.overallStatus(under:)`; `QuotaMonitor.statusPolicy` read live from the burn-rate settings; alerts, pills, cards, Touch Bars, status export and Notify! all read under it. Left: `menuBarLabel(…)` still takes the two burn-rate values instead of the policy, and pace falls back to `quotaType.duration` when no window is known | the menu-bar label takes the policy; the `Window` law removes the guess; `StatusColorPolicy` (colours, high contrast) moves to the App |
| `Account.budget` | two one-off settings: `app.claudeApiBudget` (+ `…Enabled`, edited in Claude's card) and `bedrock.dailyBudget`; Bedrock turns its budget into a fake `Daily Budget` quota | a `Budget` beside the account's `Cost`, judged as `BudgetStatus`, never a quota; the old keys read as the default account's budget |
| page state | `MenuBarLabel`, `CountdownColon`, `PopoverContentHeight`, `MenuBarStackedSize` in `Domain/Provider`; `menuBarLabel(…)` on `QuotaMonitor` | the App |
| `ProviderDefinition` · *Add Provider* | **built** (#354): *Start from API · CLI · File · Copy a provider* → *Connect* (*Test Connection*) → *Map fields* (click a value, live card; money, % used/left, a balance; a CLI's text by its line) → *Look* → *Save*; `ProviderDraft` → `ProviderCatalog` (`~/.claudebar/providers/<id>.json`, origin custom, minted id) and the key in the vault (`setting`); *Delete*. Not yet: *Edit*, several quotas from one response | Export/Import (#355); Edit |

### The order of the work

Each step ships green and changes no behaviour a user can see, until the last.

1. **Carve the modules** — move files into `Modules/<Context>` with no
   renames; page state leaves the domain. Typealiases keep call sites
   compiling.
2. **One `Provider` and one `DataSource`** — the generic lifecycle, and the
   workers Codex needs; Codex becomes `codex.json` first, because its five
   jobs exercise the most workers with the least account logic.
3. **Profile and form as data** — remove the `switch id` tables and the
   per-vendor settings protocols.
4. **`Left` and `Window`** — the two kernel laws; the eight balance definitions
   map money only.
5. **Every other provider becomes JSON** — each one may add a case and a worker,
   never a vendor type; extensions become definitions with a `script` fetch; *PROBE
   MODE* becomes *DATA SOURCE*.
6. **Add Provider** — the sheet, Test, Save.
7. **The words** — `Usage` (`updatedAt`), `Plan`, `Cost`, and remove the
   typealiases. The popover's *No quota data* · *Waiting for quota data* become
   *usage data*: a balance-only provider has no quota, but it has usage.

## 9 · Open

- **Usage History on the usage.** Claude attaches *TODAY'S USAGE* to its
  snapshot today, and the background poll skips it (issue #204). Is it a
  second read the popover asks for, or does `Usage` carry it?
- **The mapping's reach.** When a vendor's response needs a rule the JSON
  mapping cannot say (Codex's free plan with no limits; Claude's PTY screen),
  the answer is a mapping FEATURE every provider gets — never a vendor
  escape hatch. Which features, is found provider by provider.
- **Cost lines.** Bedrock reports cost per model, and an extension can report
  metrics. Is that one `Cost` with lines, or a third kind of `Left`?
- ~~**A custom provider with accounts.**~~ — **answered**: the provider's.
  The form has two scopes; an account fills the ACCOUNT scope (one API key
  each, as a reference), and *Add Account* is that form. One definition
  serves every account (§1, §5).
- ~~**`command` fetches from the UI.**~~ — **answered by the journey**
  ([USER_JOURNEYS F10](USER_JOURNEYS.md#3--what-the-journeys-changed)): the
  picker offers *CLI*, because a person typing their own command runs it with
  their own rights, as an extension does; a CLI provider that arrives by
  *Import* shows its command and asks before anything is saved or run.
- **Status in the kernel or the policy.** Is `Quota.status` a read that takes
  the policy, or does the Monitor apply it? §4 assumes the first.
