---
description: How each case a provider definition can use works — what the person sees and the one piece behind each, settings in one form with two scopes, HTTP in steps, commands and terminals, worded failures; read before adding a fetch, credential or setting case.
---

# ClaudeBar — the engine

> **#5 of 5** in [the design](ARCHITECTURE.md) · **Answers:** how each case
> works — every fetch, credential, setting and CLI rule a definition can use ·
> **Builds on:** [MODULAR_DESIGN.md](MODULAR_DESIGN.md) · **Next:** the
> provider's own `docs/providers/<id>/design.md`
>
> Split out of TARGET_ARCHITECTURE with its numbers kept, so *TARGET §8.2.x*
> still names this text; a bare § elsewhere here is TARGET's.

## 8.2 · The engine the remaining migrations share

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

### 8.2.1 · What the person sees, and the one piece behind each

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

### 8.2.2 · Settings: one form, two scopes

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

**This is slice 3's form.** Settings draws it (`ProviderSettingsSection`) for
every definition-driven provider that has no card of its own yet; the Region
and API-key cards of the providers that migrate go, and no new Swift card
comes.

### 8.2.3 · HTTP in steps, instead of a planner script

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

### 8.2.4 · A command, and a terminal

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

### 8.2.5 · A worker reports a fact; the definition words it

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

### 8.2.6 · A case answers for itself

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
  `ProviderDefinition.runningCLI` read the case's own answer; the Add Provider
  sheet asks the definition (`neededSettings`), not the lookup's cases.
- **Adding a case is:**
  - the enum line
  - its payload with its `Connection`
  - its worker
  - one factory line

### 8.2.7 · Kept as they were, and left out

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
