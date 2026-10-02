---
description: Contributor design for multiple accounts under one provider — how Monitor, Provider, Account, DataSource, the definition's accounts block, settings and the vault talk to each other; the three ways to add an account as data; the laws and their owners; and how PR #358 is refactored onto this shape without vendor code. Read before touching Add Account, account naming, sign-in or per-account keys.
---

# Multiple accounts: design — "Add Account"

User guide: [README.md](README.md).

**Status: DESIGN.** Built today (#356): one `Provider` owns `[Account]`; an
added login runs the **same** data sources with `accounts.patch` merged in and
`{{account.x}}` filled from its values; added by `accounts.folder` — Codex
only. PR #358 adds Claude (as data — kept), browser sign-in, rename and
compact labels (kept, reshaped below), and a Swift bridge that gives the 18
legacy providers, custom definitions and extensions accounts (replaced by this
design — see [§ What is wrong today](#what-is-wrong-today)).

This document owns **the account: how one is added, named, isolated and
refreshed**. Its neighbours own the rest:

| For | Read |
|---|---|
| what a Provider, DataSource, Usage *is* — the words and the tree | [CANONICAL_MODEL.md](../../architecture/CANONICAL_MODEL.md) |
| how a definition runs, the closed sums, the migration slices | [TARGET_ARCHITECTURE.md](../../architecture/TARGET_ARCHITECTURE.md) |
| which module a file lives in | [MODULAR_DESIGN.md](../../architecture/MODULAR_DESIGN.md) |
| Codex's folder and identity rules, as JSON | [providers/codex/design.md](../../providers/codex/design.md) |
| where settings and keys are stored | [settings.md](../../settings.md) |

---

## What the product already says

```text
  "Add Account…"                    ← an account is ADDED to a provider; it is not a provider
  "Sign in with browser"            ← one way to add: run the vendor's own login, in a new folder
  "Choose Signed-in Folder"         ← another: point at a folder a login already lives in
  "API KEY" (on the Add Account form) ← a third: fill the provider's ACCOUNT-scope settings
  "work@acme.com" on the pill       ← an account is told apart by WHO it is
  "Rename"                          ← …or by the name the person gave it
  "Remove"                          ← forgets it HERE; never signs out the CLI
  "This folder now signs in to someone else" ← identity is checked, and a mismatch fails closed
```

The finding: **adding an account never adds code.** Each of the three ways is
something the definition *says*; the screen only renders what it says.

## The one sentence

**A provider is fetched one way for all its logins; an account is one login —
its values fill the definition's `{{account.x}}` and its secrets come from its
own corner of the vault.**

```text
                       codex.json / claude.json / <custom>.json
                       ┌──────────────────────────────────────┐
                       │ dataSources: [ … {{account.home}} … ] │  written ONCE
                       │ accounts: { add, patch, identity }    │
                       └──────────────────┬───────────────────┘
                                          │  patched + filled per login
             ┌────────────────────────────┼────────────────────────────┐
             ▼                            ▼                            ▼
     Account  "codex"            Account "codex.7f3a"          Account "codex.c19e"
     values: {}                  values: {home: ~/A}           values: {home: ~/B}
     vault: provider.codex.*     vault: provider.codex.        vault: provider.codex.
                                        account.7f3a.*                account.c19e.*
             │                            │                            │
             ▼                            ▼                            ▼
       [DataSource]                 [DataSource]                 [DataSource]
       bound once,                  bound once,                  bound once,
       own cache                    own cache                    own cache
```

---

## What is wrong today

PR #358 reaches the right screen through the wrong shape. The evidence, in its
diff:

| Cost | The evidence |
|---|---|
| **Two lifecycles in `Provider`** (SRP) | `Provider.swift`: a `convenience init(…makeAccountSource:)`, `accountSources: [String: any AccountUsageSource]`, and an `if let source = accountSources[…]` branch at the top of `isAvailable`, `refresh`, `backgroundRefreshFloor`, `dashboardURL` — a second copy of in-flight dedupe, `isSyncing`, identity check and succeed/fail |
| **A probe by another name in a module** | `Modules/Providers/Sources/AccountUsageSource.swift` — `isAvailable()` + `refresh()` is `UsageProbe` |
| **`switch id` tables** (OCP) | `AccountConnectionRecipe.builtIn` (18 ids), `LegacyAccountConnections.source` (15 ids, builds each `XxxUsageProbe`, hard-codes `.omp/agent/agent.db`, kiro's sqlite path), `credentialKey` (6 ids), `ProviderAccountsCard` (`switch provider.id` for regions). Adding a provider edits 4 Swift files |
| **A data source copied per login** (breaks [CANONICAL §5](../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them)) | `CustomAccountConnections` builds a whole `Provider` from a re-serialised `scopedDefinition` for each added account and wraps its `defaultAccount` |
| **Vendor knowledge in Swift** | `BrowserAccountLogin` defaults to `CODEX_HOME` and Codex's `login` args and strips `OPENAI_API_KEY`…; `excludedEnvironment` lists ~40 vendor variables; `BinaryLocator` knows `"\(tool)-cli/\(tool.capitalized)CLI.app"` |
| **Throw-away work** | new init parameters on probes slices 2 and 5 delete (`homeDirectory`, `storedKeyOnly`, `failOnAllRegionFailures`, `accountToken`), `isolatedAccountCredentials` through `JSONSettingsRepository` |
| **A runtime downcast for a law** | `Account.label`'s getter: `provider.settings as? AccountNamingSettingsRepository` |
| **A crash at launch** | `ClaudeBarApp.init`: `preconditionFailure` when a legacy account source fails to build |

---

## 1 · Ubiquitous language

| Term | Meaning | Not to be confused with |
|---|---|---|
| **Provider** | the product you pay; how to fetch, once for every login | an account |
| **Account** | one login you pay for: who, its values, what we last saw | a data source; a provider |
| **default account** | the plain login the CLI already uses; id = provider id; never removed | "the first added one" |
| **added account** | a login beside it; id `<provider>.<acct>` | a copy of the provider |
| **account values** | the account-scope settings that fill `{{account.x}}` — a folder, a login id, a region | secrets |
| **account secret** | an account-scope secret (an API key) — a *name*, its value in the vault under that account | a value in `settings.json` |
| **way to add** (`accounts.add`) | how the definition lets a person add one: `folder` · `signIn` · `form` | a data source kind |
| **identity** | the fact that names a login (email, account id) and the rule that a fetch must still match it | the label |
| **label** | the name a person gave an account ("work") | the email |
| **display name** | what the pill says: label, else email, else the provider's name | the menu bar label |
| **menu bar label** | the shortened text in the 16 px status item — the page's, not the model's | display name |

*Account*, not *connection*: #358 called added logins "connections" in Swift;
the screen says *Account* and so does CANONICAL. *Connection* stays the word
for *Test Connection* (a fetch), where it already means something else.

## 2 · The aggregate — from the root down

```text
Monitor ◆                                  the menu bar's root
├── providers: [Provider]
├── lineup → [Account]                     DERIVED — enabled accounts of enabled providers: the pills
└── selection: Account.ID
     │
     └── Provider ◆                        THE PRODUCT — one lifecycle for every login
         ├── definition ◇                  the JSON — written once
         │   ├── dataSources               may say {{account.x}}
         │   └── accounts: Accounts? ◇     NIL = this provider has one login, and no "Add Account"
         │       ├── add: AddAccount ◇     THE WAYS TO ADD — a closed sum, one or more:
         │       │     folder(rule)          "Choose Signed-in Folder" — read facts from a folder
         │       │     signIn(command)       "Sign in with browser" — run the vendor's login into a
         │       │                           NEW folder, then the folder rule checks it
         │       │     form                  fill the form's ACCOUNT-scope settings (an API key, a region)
         │       ├── patch                 by data source kind: what an added login changes (RFC 7396)
         │       ├── identity              which fact names the login; a mismatch fails closed
         │       └── nameFromEmail         the email names the pill
         ├── settingsForm ◇                [Setting], each with a SCOPE: provider | account
         ├── accounts: [Account] ◆         NEVER EMPTY; [0] is the default
         │   └── Account ◆                 A LOGIN — no behaviour of its own
         │       ├── id                    `<provider>` · `<provider>.<acct>` — pins and settings keyed by it
         │       ├── label?                the person's name for it
         │       ├── values                account-scope settings (non-secret)
         │       ├── isEnabled             pause, not forget
         │       ├── usage? · sync         what we saw · fetch health — kept apart
         │       └── displayName           DERIVED — label ?? email ?? provider.name
         ├── bound: [Account.ID: [DataSource]]   internal — made ONCE per login from the patched,
         │                                       filled definition, with that login's vault
         └── refresh(account) · add(…) · rename(account, to:) · remove(account)

DataSource ◆                               ONE type; never knows there are accounts —
                                           it sees a definition already filled for one,
                                           and a SecretStore already scoped to one
```

**What varies is data.** There is no `AccountUsageSource`, no recipe table, no
per-vendor connection class: a provider that can have accounts says so in
`accounts`; one that cannot has `accounts: nil` and its card has no *Add
Account* button. A legacy provider (still a Swift `XxxProvider`) has
`accounts: nil` by construction — it gains accounts in the slice that turns it
into JSON, and not before.

### `AddAccount` — the ways to add, a closed sum

| Case | JSON | Carries | What it does |
|---|---|---|---|
| **folder** | `"folder": { savedAs, default, accountId: {fact, savedAs}, derived?, notSignedIn }` | where the login lives, which fact names it | reads the folder through the definition's own credential/context lookup (filled with that folder), refuses the default folder and duplicates, saves `{savedAs: folder, accountId.savedAs: fact}` |
| **signIn** | `"signIn": { cli, args, homeVariable, unset, timeout }` | the vendor's login command | makes `~/.claudebar/accounts/<provider>/<uuid>/` (0700), runs `cli args` with `homeVariable=<folder>` and `unset` removed, waits; on exit 0 hands the folder to **folder** with `madeBy: .signIn` — never saves anything itself |
| **form** | `"form": true` | — | renders the form's account-scope settings; non-secrets → `values`, secrets → the account's vault; then *Test Connection* with them before saving |

`signIn` requires `folder` (it ends in one). `derived` — #358's
`derivedValues`, e.g. Claude's Keychain service `Claude Code-credentials-<hash8>`
— is a feature of the folder rule, so stays.

### `Account` — one login

> **Pointable as:** the *work@acme.com* pill.

| | |
|---|---|
| **Owns** | its id, label, values, enabled flag, last usage and sync state |
| **Tell it** | nothing — the provider tells it `succeed(usage)` / `fail(error)` |
| **It answers** | `displayName`, `status`, `email` (usage's, else what it was added with) |
| **Never** | fetches; reads settings; downcasts a repository; knows a vendor; carries a secret's value |

### `Provider` — the lifecycle, once

> **Pointable as:** the *Codex* row in Settings → Providers.

| | |
|---|---|
| **Owns** | which data source is active, the fallback, the in-flight refresh per account, binding each account's data sources |
| **Tell it** | `add(_ config)`, `rename(account, to:)`, `remove(account)`, `refresh(account, kind)`, `use(kind)` |
| **It answers** | `accounts`, `status`, `bestAccount`, `canAddAccounts` (`definition.accounts?.add` non-empty) |
| **Never** | has a second refresh path; holds an `AIProvider` inside it; switches on its id |

---

## 3 · How the pieces talk

### 3.1 · Launch

```text
ClaudeBarApp.init (composition root)
  │
  │ ProviderCatalog → [ProviderDefinition]          bundled · ~/.claudebar/providers · (extensions, slice 5)
  │ settings.accounts(forProvider: id) → [ProviderAccountConfig]
  ▼
Providers.make(definition, settings, vault)
  │
  ├─ default account:  definition.dataSources ──map──▶ DataSources.make(_, secrets: vault.scoped(nil))
  │
  └─ for each config:  provider.add(config)
        │  definition.dataSources(forAccount: config.values)     patch merged, {{account.x}} filled
        │  ── a data source the patch nulls is left out for that login
        ▼
        DataSources.make(_, secrets: vault.scoped(config.accountId))
        │
        └─ fails (bad folder, unfilled {{account.x}})?  → logged by account id, account left out.
                                                          The app never crashes.
  ▼
QuotaMonitor(providers) → lineup = provider.accounts.filter(isEnabled), for every enabled provider
```

Legacy providers enter the lineup as today: one `AIProvider`, one pill.

### 3.2 · Add Account

```text
 ProviderAccountsCard                      (renders definition.accounts.add — no switch on id)
   │
   ├─ "Sign in with browser" ──▶ provider.signIn() ───────────────────────────┐
   │                               │ AccountSignIn (DataSources worker)        │
   │                               │   mkdir ~/.claudebar/accounts/<p>/<uuid>  │
   │                               │   run signIn.cli signIn.args              │
   │                               │     env[homeVariable] = folder            │
   │                               │     env -= signIn.unset                   │
   │                               │   exit 0? else throw (folder removed)     │
   │                               ▼                                           │
   ├─ "Choose Signed-in Folder" ─▶ AddedAccounts.check(definition, folder) ◀───┘
   │                               │ definition.dataSources(forAccount: {folder})
   │                               │ → its credential + context lookups → facts
   │                               │ refuse: default folder · duplicate · no login
   │                               ▼
   │                             ProviderAccountConfig { accountId: uuid, email, values }
   │
   └─ "Add Account" (form) ─────▶ form's account-scope settings
                                   │ secrets → vault.scoped(uuid).save(name, value)
                                   │ provider.testConnection(draft) — before saving
                                   ▼
                                 ProviderAccountConfig { accountId: uuid, values }
                                   │
                                   ▼
               settings.addAccount(config) ; provider.add(config) ; monitor.add(account)
```

One door in: `provider.add(config)`. The three ways differ only in how the
config is *found*; none of them builds a data source.

### 3.3 · Refresh one account

```text
QuotaMonitor.refresh(account)
  ▼
Provider.refresh(account, kind)            in flight already? → await that task
  │  bound[account.id] → active DataSource (and its fallback chain)
  ▼
DataSource.fetchUsage()                    already filled for this login; vault already scoped
  │  lookUp()  ── credential from {{account.home}}/auth.json · vault account.<acct>.apiKey
  │  identity  ── the looked-up fact == the saved one?  no → DataSourceError(.lookup, sessionExpired(hint))
  │  cache?    ── per DataSource, so per login
  │  fetch → map
  ▼
Provider: account.succeed(usage, from: kind)   |   account.fail(error)  (usage kept)
```

Identity is checked where the credential is read — **once, in the lookup** —
not again in `Provider` and not before the cache.

### 3.4 · Rename · Remove · menu bar

```text
"Rename"  → provider.rename(account, to: "work")
              settings.setLabel("work", account: account.id)      ONE store for default and added
              account.label = "work"
"Remove"  → provider.remove(account)                               never the default
              settings.removeAccount · vault.scoped(acct).deleteAll · bound/refreshTasks dropped
              config.madeBy == .signIn → its folder is deleted too (ClaudeBar made it, nobody else uses it)
              a folder the person chose, and the CLI's own files, are never touched
Menu bar  → MenuBarLabel(accounts.map(\.displayName))              App — shortens, numbers collisions
```

---

## 4 · Invariants — each law, one owner

| Law | Owner |
|---|---|
| a provider has at least one account; the default's id is the provider id, an added one's `<provider>.<acct>` | `Provider.accounts` |
| one definition serves every account — an added login's data sources are the definition patched and filled, never a hand-built copy | `ProviderDefinition.dataSources(forAccount:)` |
| a provider without `accounts` cannot add one — the button is absent, not disabled | `ProviderDefinition.accounts` |
| an account's secret is read only from that account's vault corner; a missing one is *Key needed*, never the default's key or the environment | `ProviderVault.scoped(_:)` |
| an added login's CLI never sees the default login's credentials: what to set and unset is the definition's `patch`, per data source | the definition (data) — run by `CLIFetcher` |
| usage shown under a login was fetched with that login's credential; a different identity fails closed with the definition's hint | `DataSource` (lookup) |
| a folder already listed, or the default folder, is not added twice | `AddedAccounts` |
| sign-in never writes to an existing folder and saves nothing on failure, cancel or timeout | `AccountSignIn` |
| display name is label, else email, else the provider's name | `Account.displayName` |
| one refresh per account in flight; a failed refresh keeps the last usage | `Provider` |
| removing deletes only what ClaudeBar made — the account's settings, its vault corner, and its folder when `madeBy == .signIn`; never a folder the person chose or the CLI's files | `Provider.remove` |
| a data source whose key lookup ClaudeBar cannot see (`fetch: script`) declares an `identity`, or the definition is refused on load | `ProviderDefinition` validation (`DefinitionError`) |
| the data source choice is the provider's; a login the patch leaves without it uses the next on the fallback chain, and its usage says which | `Provider` |
| a menu bar label is shortened for width and never widens to a full email | `MenuBarLabel` (App) |

Two laws #358 put in two places, now one each: the identity check (it ran in
`DataSource` **and** in `Provider.refresh`'s bridge branch) and display naming
(in `Account.name`, `Account.accountDescription` **and** `StatusItemLabelDriver`).

## 5 · The tells

```swift
// Card
if provider.canAddAccounts { AddAccountMenu(ways: provider.definition.accounts!.add) }
try await provider.signIn()                                    // signIn ∘ folder ∘ add
try provider.add(AddedAccounts.check(provider.definition, folder: url, existing: settings.accounts(forProvider: provider.id)))
provider.rename(account, to: name)
provider.remove(account)

// Composition root
let vault = ProviderVault()
Providers.make(definition, settings: settings, vault: vault)   // binds every saved account

// Page
Text(account.displayName)
MenuBarLabel.labels(for: monitor.lineup)
```

Not: `LegacyAccountConnections.shared.recipe(for: provider.id)`,
`switch provider.id { case "minimax": … }`, `settings as? AccountNamingSettingsRepository`.

---

## 6 · Refactoring PR #358

| #358 piece | Becomes |
|---|---|
| `claude.json` `accounts` (folder, patch, identity, `derivedValues`) | **kept** — re-flow the file to its original formatting |
| context identity (`"context.account.email"` parsed as a string) | `identity.field` decoded as a typed `credential(name)` \| `context(file, field)` |
| `DataSource.fetchUsage` checks identity before the cache | identity checked in `lookUp()` only |
| `BrowserAccountLogin` (Infrastructure, Codex defaults) | `AccountSignIn` worker in `DataSources`, driven by `accounts.add.signIn` in `codex.json` / `claude.json`; process behind the existing `CLIExecutor`-style port |
| `BinaryLocator.findInApplicationBundles` | the definition's `cli` gains `alsoAt: [paths]`; the locator checks what it is told |
| `Provider.rename`, `ProviderAccountConfig.named` | **kept**; default account's label stored by `MultiAccountSettingsRepository.setLabel(_:account:)`, which `Provider` receives typed — no downcast |
| `Account.name` / `accountDisplayName` / `accountDescription` / `isNamedByAccount` | one `displayName`; the tooltip's "name (email)" is the page's |
| `AccountMenuBarLabel` (Domain) | `MenuBarLabel` in App ([CANONICAL §1](../../architecture/CANONICAL_MODEL.md#1--the-tree): not in the model) |
| `ProviderAccountsCard` | **kept**, rendering `accounts.add` cases and the form's account scope; no `switch provider.id` |
| `CodexAccountsCard` | folded into `ProviderAccountsCard` |
| `withDailyUsage` / `guestPasses` default-only | a definition flag on the capability (`dailyUsage.accounts: "default"`), so the rule is written down |

### What dies

`AccountUsageSource` · the bridge `Provider.init(profile:…makeAccountSource:)`
and `accountSources` · `LegacyAccountUsageSource` · `LegacyAccountConnections` ·
`AccountConnectionRecipe` · `AccountCommandContext` · `CustomAccountConnections`
· `ExtensionAccountConnections` · `ScopedCredentialRepository` (→
`ProviderVault.scoped`) · `AccountNamingSettingsRepository` · the probe init
parameters added for accounts · `isolatedAccountCredentials` ·
`docs/features/multi-account/universal-design.md` (this doc replaces it) · the
per-provider "Accounts" paragraphs for providers that have `accounts: nil`.

## 7 · Build sequence

Each slice one PR, test first, green.

| # | Slice | Pins |
|---|---|---|
| 1 | **Claude accounts as data** — #358's `claude.json` block, typed `identity`, identity in lookup only; `ClaudeAccountsTests` | a Claude folder adds; another email in it fails closed; default untouched |
| 2 | **Rename + display name** — `Account.displayName`, `setLabel` for default and added, `MenuBarLabel` in App | labels survive relaunch; one login shows the product name; collisions number, never widen |
| 3 | **`accounts.add` sum + `signIn`** — `AccountSignIn` worker, `codex.json`/`claude.json` declare it; `cli.alsoAt` | cancel/timeout/fail leave no folder and no config; env carries only `homeVariable`, `unset` removed; *Remove* of a signed-in account deletes its folder, of a chosen one never — README's *Remove* paragraph updated |
| 4 | **one Accounts card** — renders `accounts.add`; `CodexAccountsCard` goes | a provider with `accounts: nil` shows no button |
| 5 | **`form` + `ProviderVault.scoped`** — account-scope settings in the form; custom definitions can declare `accounts` | an added account's missing key is *Key needed*, never the default's |
| — | legacy providers | gain accounts in TARGET slices 2 and 5, when they become JSON — by adding an `accounts` block, nothing else |

## 8 · Open questions

Each answered from two questions: *what does the person believe they did?*
and *who owns the thing?* — never from what is easiest to build.

- ~~**Sign-in folder lifetime** — delete the folder `signIn` made on *Remove*?~~
  **Yes — and only that folder.** The person never saw that folder. What they
  did was *"sign in to my work account inside ClaudeBar"*, so *Remove* means
  *"ClaudeBar, stop holding my work login"*. A folder left behind is a live
  refresh token nobody can see, which is the opposite of what they asked for.
  A folder the person *chose* is theirs, and their terminal may use it, so it
  is never touched. The difference is **who made it**, so it is recorded when
  the account is added (`ProviderAccountConfig.madeBy: .signIn | .folder | .form`).
  It is never guessed from where the folder is. The confirmation says so:
  *"Removes work@acme.com from ClaudeBar and deletes the sign-in ClaudeBar
  kept for it."* (§3.4, §4)
- ~~**Extensions** — give them accounts before slice 5?~~ **No. They get them
  the same way every provider does, when they can say how.** To the person, an
  extension is just a provider (*Built in · Custom · Extension*). So the
  question is not *"is it an extension?"* but *"can this provider say how an
  account is added and kept apart?"*. A script is code ClaudeBar cannot see
  into. ClaudeBar can pass a login's values to it, but cannot know whether the
  script respects them. So when extensions are read as definitions (slice 5),
  their manifest declares an `accounts` block like anyone else's. **A data
  source whose key lookup ClaudeBar cannot see (`fetch: script`) must declare
  an `identity`, or the definition is refused on load.** That makes the
  script's own answer the proof, and a script that ignores its scope fails
  closed instead of showing one login's usage under another. (§4)
- ~~**Bedrock's per-profile budget** — account-scope fields on a legacy card?~~
  **A second AWS profile is a second account, and its budget is that
  account's.** The person's words are *"my limit for the work AWS account"*.
  The budget belongs to the login whose money it guards
  ([CANONICAL §5](../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them):
  a budget judges one account's cost). Bedrock gets this when it becomes JSON
  in slice 5:
  - `accounts.add.form` with `profile` as an account value, chosen from
    `~/.aws/config`;
  - `budget` as an account-scope setting.

  Until then Bedrock has one account, and today's `bedrock.dailyBudget` is
  that account's budget. There is no interim adapter.
- ~~**One data source choice, or one per account?**~~ **One, the provider's.**
  *DATA SOURCE* sits on the provider's card, and to the person it means *"how
  ClaudeBar asks Codex"*, not *"how it asks for work@"*. An added login whose
  `patch` leaves out the active kind (a form account with only a key has no
  CLI) uses the first remaining data source on the active one's fallback
  chain. Its pill says which one (*via API*), so the difference is never
  silent. *Designed, not built:* today `Provider.dataSource(_:for:)` returns
  nil and the refresh throws `noData`. (§4)
- ~~**Can the default account be renamed?**~~ **Yes.** Two people with
  *personal* and *work* logins do not think of one of them as the "default".
  That is ClaudeBar's word for the login the CLI already uses. *Rename* works
  on every account. *Remove* is the only command the default refuses, because
  that login belongs to the CLI. (§3.4)
- ~~**One Swift adapter so every provider has accounts now?**~~ **No.** It
  builds a second lifecycle and four `switch id` tables, and every line of it
  is deleted when the provider becomes JSON (§ What is wrong today).
