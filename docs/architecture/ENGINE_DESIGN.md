---
description: How each case a provider definition can use works — what the person sees and the one piece behind each, settings in one form with two scopes, HTTP in steps, commands and terminals, worded failures; read before adding a fetch, credential or setting case.
---

# ClaudeBar — the engine

> **#5 of 5** in [the design](ARCHITECTURE.md) · **Answers:** how each case
> works — every fetch, credential, setting and CLI rule a definition can use ·
> **Builds on:** [MODULAR_DESIGN.md](MODULAR_DESIGN.md) · **Next:** the
> provider's own `docs/providers/<id>/design.md`

## 1 · What each provider needed, as a general rule

Claude needed more than Codex, and every provider after it brought its own
needs; each became a generic piece, never a vendor type:

| Need | Generic piece |
|---|---|
| a TUI screen and human reset dates no rule can say | `Mapping.script` — a JavaScript file in JavaScriptCore, no I/O, host `humanDate()`; the scripts ship beside the definition. `values` hands it settings (`{{setting.x}}`); a blank one isn't there, and the script never writes one back |
| Claude Code's Keychain item | `CredentialLookup.keychain(service, fields)` via `security`, hex-decoded, written back as compact JSON |
| expiry in milliseconds, a JSON refresh body with `scope` | `OAuth2Refresh.dueWhen`, `bodyFormat`, `scope`; values keep their JSON type on write-back; a failed refresh re-reads the store |
| another CLI's Keychain login (`gh`, go-keyring) | `keychain.account`, `keychain.encoding: goKeyringBase64`; an encoded item is never written back |
| one report covering many accounts (Oh My Pi) | a script quota's `group`, and `notes` — a row under a group with nothing to measure |
| a cloud's metrics priced into money (Bedrock) | `cloudWatch` with `prices`: `CloudWatchClient` and `PriceCatalog` ports, implemented in `AWSClients`; a script prices them exactly (`decimalMultiply`) into one `Cost` with lines |
| an app's own server on this Mac (Antigravity) | `localServer`: the process by name and command line, values from its arguments, its listening ports, declared loopback paths; readiness without starting a process |
| a login file a CLI renews itself (Gemini) | `refresh: {"cli": …}` beside `oauth2`: on a 401 the CLI runs and the file is read again; the refresher says it doesn't write back |
| a console session: one cookie read out of the Cookie header (`sec_token`, a CSRF cookie), a header left out when its value is missing | `"cookies"` on a credential lookup; `dropEmpty` covers headers |
| `env`, ready markers and a rendered screen for the CLI; a TUI that discards input typed during its startup paint | `CLICall.environment`, `readyWhen`, `screen`, `inputDelay` |
| `/cost` only for API-billed accounts; API→CLI only while a setting allows | `fallbackOn` (hand-off by failure) and `fallback.enabledBySetting`; the provider follows the chain and reports the first real failure |
| 15-minute cache, a remembered 429 | `cache.ttl` (also the background floor) and rate-limit memory on `DataSource` |
| the account's email and billing type | `context` files handed to the mapping |
| the folder-trust prompt | `recover.patchJSONFile`, tried once |
| Codex logins in their own folders (#326) | `accounts` (`folder`), `{{account.x}}`, `identity` (fail closed when a folder signs in to someone else), `requiresFiles` (#216), `verifyBeforeBackground`, JSON-RPC `then` + `environment`, `#jwt.claim` and `$credential.` paths |
| the usage API's model limits, plan and money | JSON mapping rules, not a script: `each` + `where`, names by `firstWord`/`lowercase`, `unique` (first wins), `overLimit` (negative left), `countdown: "hours"`, `plan.plans` from `$credential.`, and a list of `cost` shapes with `when` and exact `{amount, decimals}` minor units |
| today's usage and guest passes | `UsageHistory` beside the providers (read with the popover open, never in the background; keyed by the login whose logs it reads) and the `GuestPasses` capability |
| Claude logins in their own config folders | `accounts.folder` with `email` and `accountId.field` as an `IdentityField` (`$context.account.email`), `derived` values (the Keychain service, from a sha256 of the folder), `identity` read from a context file; today's usage and guest passes stay with the default login |

## 2 · The engine

Seventeen migration PRs (#381–#398) were built against slices 2 and 5, and
every one of them edited the same Swift:
- `ClaudeBarApp.swift`, `ProvidersPane.swift` and `Provider.swift` in all 17
- `Fetch.swift` and `Fetchers.swift` in 16
- `ProviderVisualIdentity.swift` in 14

So §1's OCP promise did not hold. SRP broke in the same places:
- `HTTPRequest` grew from 5 fields to 13.
- The account form gained eight flags.
- `Provider` started checking files.

Every vendor quirk became a field, because nobody asked what the *person*
sees. This section starts there. Every piece below is something on screen, and
owns one rule.

**Tell, don't ask.** A caller never reads a piece's state to decide what that
piece could decide. The `Setting` says what a blank means, whether two values
are the same folder and where its value is kept. A worker's failure says which
fact it is. A fetch case says where it sends a key. A data source says which
one takes over when it has no key. Views may look at a kind only to draw it.

### 2.1 · What the person sees, and the one piece behind each

| On screen | The person thinks | The piece | Its rule |
|---|---|---|---|
| **API KEY · REGION · CLI DATA FOLDER** in a provider's settings and in *Add Account* | "it needs these from me" | a **`Setting`** of a **kind** (`secret · choice · path · text`) and a **scope** (`provider` · `account`): the `SettingsForm` of CANONICAL §1 | the kind checks the value |
| **REGION: China · International** | "I'm in China, so it talks to China's site" | each option of a choice setting **carries its values**: `China → site: kimi.com`. A definition says `{{setting.region.site}}` | an account's own region wins over the provider's |
| **DATA SOURCE: API · CLI** | "where it reads my usage" | `DataSource`, one active per provider | unchanged |
| **KEY LOOKUP ORDER · COOKIE SOURCE** | "where it finds my key" | `CredentialLookup`, adding **`browserCookies`** | the first that answers wins |
| *Start from: **API** · **CLI** · File* | "call a URL" · "run a command" | `Fetch.http` (with **steps**) · `Fetch.command` (a command over pipes). A TUI that only draws in a terminal stays `Fetch.cli` | one worker each |
| ***Test Connection*** → ***Response*** | "show me what came back" | the response of the last step that ran | stops before mapping |
| *Couldn't read your key · Couldn't connect · Couldn't find the numbers* + what to do | "which step broke, and where do I go" | `DataSourceError(step, reason)`, the reason worded by the definition's **`errors`** | no response body, no secret |
| *Import:* ***sends your key to …*** · ***runs …*** | "where does my key go, what will it run" | each fetch case's **`Connection`** answers for itself | every host a setting can pick is listed |
| ***Configured*** | "it will work" | `isReady` of the data source a refresh would end on | follows the no-key hand-off |
| *Add Account* → saved | "my key is kept" | the vault, read back before the account is kept | nothing half-saved |

### 2.2 · Settings: one form, two scopes

```json
"settings": [
  { "id": "apiKey", "label": "API key", "kind": "secret", "scope": "account" },
  { "id": "region", "label": "Region", "scope": "account", "default": "china",
    "kind": { "choice": [
      { "id": "china",         "label": "China",         "site": "kimi.com" },
      { "id": "international", "label": "International", "site": "kimi.ai" } ] } },
  { "id": "home", "label": "CLI data folder", "scope": "account", "default": "~/.kimi",
    "kind": { "path": { "mustExist": true } } }
],
"fetch": { "http": { "url": "https://www.{{setting.region.site}}/apiv2/…/GetUsages",
                     "headers": { "Origin": "https://www.{{setting.region.site}}" } } }
```

**Why one form instead of `choices` plus form flags.** The person sees one
*REGION* control, not a setting and a separate choice. A choice that carries
its values replaces the four `…BySetting` fields and the
`"value": "{{account.x}}"` patches. `{{setting.<id>}}` and
`{{setting.<id>.<value>}}` fill any string of a definition — a URL, a header,
a cookie domain, the dashboard link. `Provider` fills them for each login when
it makes that login's data sources, as it fills `{{account.x}}`;
`provider.set(_:to:)` saves a value and makes every login's data sources again,
so a changed *Region* needs no restart. A secret fills nothing: a key reaches
a fetch only through its credential lookup.

**Scope is the person's model of logins.**
- **Provider scope.** The value is the same for every login, like *ENV VAR
  NAME*. It is kept under `<id>.<setting>` — today's `minimax.region` and
  `kimi.region` — so no setting moves.
- **Account scope.** Each login has its own value; *Add Account* asks for
  exactly these. The default login's value is the provider-scope one, which is
  why it lives under the same key.
- **A setting only some data sources use says so** (`"for": ["api"]`): Kimi's
  session token is the API's, its signed-in folder the CLI's. *Add Account*
  asks only for what the active data source uses (`provider.accountForm`),
  and a login added without such a value runs only the sources that don't
  need it.

**The rules sit with whoever holds the data.**
- **Each kind owns its rule.** `setting.check(value, paths:)` returns the
  sentence the sheet prints; `setting.value(from:)` says what a blank means
  (the default, or a choice's first option); `setting.keep(_:in:)` puts a
  secret with the vault's keys and anything else with the saved values.
  - A secret has no default.
  - A choice takes only its options.
  - A path can be required to exist; `paths` is a `@Mockable` port.
- **"Two logins never share a path" belongs to `Provider`.** Only `Provider`
  knows every login's values, the default one included; it asks the setting
  whether two values are the same place (`isSamePlace`). No `notIn` list is
  written in the JSON.

**Old files still decode.** Today's `accounts.form` (`"secret": true`,
`"choices": […]`) reads as account-scope settings.

**One form for every provider.** Settings draws it (`ProviderSettingsSection`)
for every provider that has no card of its own; no new Swift card comes.

### 2.3 · HTTP in steps, instead of a planner script

The PRs needed four shapes, and all of them are *call A, then B with something
A said*:
- Command Code: `httpSequence`
- Gemini: project, then quota
- Alibaba: dashboard token, then console
- Antigravity: `workflow`

JSON-RPC already says this with `then`. HTTP says it the same way:

```json
"http": { "steps": [
  { "name": "project", "request": { … }, "optional": true, "attempts": 2,
    "keep": { "project": "$.cloudaicompanionProject" } },
  { "name": "quota", "request": { "body": "{\"project\": \"{{project}}\"}" },
    "dropEmpty": ["project"] } ] }
```

- **What a step can do.** `keep` names values from a step's response, by JSON
  path — or a list of paths, the first that answers — or by a `pattern` over
  text. `optional` lets a step fail without ending the fetch, though a
  refused key or a rate limit still ends it. `unless` skips a step when a
  value is already known, such as a `sec_token` already in the cookie.
- **Every step answers.** The response is each step's answer by name —
  `{ "whoami": {…}, "credits": {…} }`, text where it wasn't JSON — so the
  mapping reads what any step said and *Test Connection* shows them all.
- **A kept value never replaces a credential value.** A step's answer cannot
  swap the key a later step sends. A value filled into a URL is
  percent-encoded, so it can never add a query item.
- **`attempts`** (1 to 3) tries a step again after a network failure or a 5xx.
  **`dropEmpty`** leaves out a JSON body key or URL query item whose value is
  missing — `?orgId={{orgId}}` goes without `orgId` when no step found one.
- **Import lists every host.**

This replaces the JS planner (`httpFlow`), as well as `commandPlan` and
`workflow`. **It reverses the earlier decision to keep `httpFlow`.** A
planner script is the escape hatch §3 warns about: the person cannot read what
it will do, and Import cannot show it. If a provider proves a flow these rules
cannot say, that provider brings the rule in its own PR.

### 2.4 · A command, and a terminal

Two protocols, two cases — never one type with a mode flag, where half the
fields would mean nothing in each mode.

| Tag | Meaning | Worker |
|---|---|---|
| `command` | run a command over pipes; read its output; its exit code is a fact | `CommandFetcher` (`PipeCLIExecutor`) |
| `cli` | drive a TUI that only draws in a terminal — Claude's `/usage`, Codex's `/status` — and capture its screen | `CLIFetcher` (the PTY executor), unchanged |

- **Nothing that exists moves.** `cli` keeps its meaning, so `claude.json`,
  `codex.json` and the files people made keep working as they are.
- ***Add Provider*'s *CLI* makes a `command`.** A command a person types is
  plain output; a TUI needs a definition written for it.
- **`{{token}}` reaches a command through its environment**, never its
  arguments, the same way it reaches a header.

### 2.5 · A worker reports a fact; the definition words it

A worker's failure is a fact that answers for itself (`ReportedFailure`): its
key in `errors`, and the reason it gives when the definition says nothing.

| Fact | Key | Without a rule |
|---|---|---|
| an HTTP status that is not an answer | `http.<status>`, else `http.default` | today's wording (`HTTP error: 500`, *Key needed* on 401/403) |
| a command's (or a terminal's) CLI is not on this Mac | `cli.missing` | *CLI not found* — a login with no usage then reads *NOT SET UP* (CANONICAL §5) |
| a command exited non-zero | `cli.nonzero` | "`acme` exited with code 2" |
| a command could not start | `cli.failed` | "`acme` could not be started" |

```json
"errors": { "http.404": "subscriptionRequired",
            "http.403": { "sessionExpired": "Sign in to the console again." },
            "cli.missing": { "cliNotFound": "kiro-cli" } }
```

- **A rule says what a fact means**, in the reasons the screen prints. Nothing
  from the response fills it: no `{{status}}`, no `{{body}}`, and no flag kept
  only to reproduce an old probe's sentence; a golden test updates its
  expected text instead.
- **Fixed rules.** A 429 is always a rate limit with its `Retry-After`, and
  `http.429` is refused. A 401 or 403 still gets the one refresh-and-retry
  first.
- **What stays on the request.** `acceptedStatuses` stays on the request,
  because which statuses are an answer is part of the protocol.

### 2.6 · A case answers for itself

```swift
public protocol Connection: Sendable {
    var urls: [String] { get }        // as written; Import spells out each setting's options
    var commands: [[String]] { get }  // "runs"
}
extension Fetch {
    public var connection: any Connection                            // the one switch, beside the cases
    public func runningCLI(_ cli: String, at binary: String) -> Fetch   // CLI LOCATION
}
```

- **Nothing else switches over the cases but the factory.**
  `ProviderSharing` (*Import*'s "sends your key to" and "runs") and
  `ProviderDefinition.runningCLI` read the case's own answer (where the CLI
  is found: §2.7); the Add Provider
  sheet asks the definition (`neededSettings`), not the lookup's cases.
- **Adding a case is:**
  - the enum line
  - its payload with its `Connection`
  - its worker
  - one factory line

### 2.7 · Where a provider's CLI is

> **Status: DECIDED** (2026-10-05, for #458; journey moment 3a) — not built.

*Where is this product's program on this Mac?* already has one answer per
product: the **CLI location**, which `runningCLI` applies to every call that
starts the CLI — each fetch, a credential refresh, Add Account's sign-in.
What is missing is only its **default** when the person chose none and the
program isn't on the PATH, but the product's own app carries one. So `cli`
says every place the program may be, in order:

```json
"cli": ["acme", "/Applications/Acme.app/Contents/Resources/acme"]
```

A bare name is looked for on the PATH, a path is taken as it is. The first
entry is the name every call runs; `"cli": "acme"` is the same as `["acme"]`,
so no definition changes unless its app carries the program.

| Law | Owner |
|---|---|
| the CLI location is the one the person chose; else the first entry of `cli` that is found. A chosen one that is missing is *CLI not found*, never another copy | `Configuration` |
| found when the provider is configured — at launch and when the CLI location changes; the PATH is asked only when a later entry exists on this Mac | `Configuration` |
| every call that starts the CLI follows the location; no call carries places of its own | `ProviderDefinition.runningCLI` |

`signIn.alsoAt`, which only sign-in read, becomes entries of `cli`; nothing
in `DataSources` changes. Which places a product uses is that provider's
research: its `design.md` ([Codex](../providers/codex/design.md#desktop-app-cli)).

### 2.8 · Kept as they were, and left out

**Kept as built in the PRs:**
- `browserCookies` + `BrowserCookieReader` (SweetCookieKit, behind a
  `@Mockable` port); its domains may name a setting
- `DecimalScript` — `jsonDecimal` and `decimalCents` in every mapping script,
  for exact money
- the *Configured* hand-off: a source with no key is configured when the one
  it hands a missing key to is (`dataSource.handOffWithoutKey`)
- the vault read-back before an added login is kept
- the Data source and Accounts sections for every JSON provider

**Folded into what exists:** `availability: files` becomes `requiresFiles`,
which now also makes a source not *Configured* while its files are missing.

**Left out, by decision:**
- **A data source per account.** One active per provider is the law; Alibaba
  and Kimi pick by data source, not by account.
- **One-provider escape hatches:** `script` credentials, a mapping that writes
  settings, page fields in script output, `bedrockUsage`.
