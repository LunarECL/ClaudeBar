---
description: Contributor design for showing another app's daily tokens, such as Claude Desktop's buddy-tokens.json (#198), as its own card in a provider's Today section, declared as `usageHistory.otherApps` in the definition. It is never a data source or a limit. Read before adding an app's local counter to a provider, or before reviewing PR #446.
---

# Other apps' usage: design

User guide: [README.md](README.md) · Mockup: [design-concept/claude-desktop-tokens](../../../design-concept/claude-desktop-tokens/index.html)

**Status: BUILT, slices 1–6 and 8; slice 7 is DESIGN.** Built on 2026-10-04 in
place of [PR #446](https://github.com/tddworks/ClaudeBar/pull/446), which adds the
same file as a third Claude data source; its fixtures are the tests here. Built:
`UsageLog.At.formatted`, whole non-negative counts, `UsageLog.OtherApp` and
`Definition.otherApps`, `UsageHistory.label` / `otherApps` / `usedOtherApps`,
Claude's entry and patch line, and the popover card. Not built: the Today section
when a provider has no snapshot (slice 7), so a user without Claude Code doesn't
see the card yet.

This document owns **an app's usage that sits beside a login's own logs**: how a
definition declares it, which login shows it, and how its days are counted.
Its neighbours own the rest:

| For | Read |
|---|---|
| how a login's own logs become days: dedup, prices, the ledger | [design.md](design.md) and [TARGET_ARCHITECTURE §10](../../architecture/TARGET_ARCHITECTURE.md#10--usage-history-as-data) |
| Claude's data sources (CLI, API) and their fallbacks | [providers/claude/design.md](../../providers/claude/design.md) |
| added logins and `accounts.patch` | [multi-account/design.md](../multi-account/design.md) |

---

## What the product already says

- The popover's **Today** cards: *Cost Usage*, *Token Usage*, *Working Time*,
  each ending "Vs Oct 3 …". Below them, *Daily usage — last 30 days*.
- Settings → Providers → Claude → **Claude Configuration**: "Data fetching method
  for all Claude accounts", with **CLI** and **API**. All of these answer one
  question: how much of my plan's limit is left.
- Settings → General → **Daily Usage Cards**: on or off.
- Claude Desktop's file, `~/Library/Application Support/Claude/buddy-tokens.json`:
  `{"tokens-today": {"date": "2026-05-28", "tokens": 74422}}`. It holds only
  today's total, and Desktop overwrites it.

The new card reuses these words: **Claude Desktop · tokens today**, with "Vs Oct 3 …".

## The one sentence

> Another app's tokens today appear as their own card in the usual login's
> Today section, beside that login's own cards. They are never a data source,
> never a limit, and never added to the login's own totals.

```
Claude popover (usual login)
├─ limits            Session 62% · Weekly 81%       ← data source (CLI / API)
└─ Today
   ├─ Claude Code    1,284,310 tokens · Vs Oct 3 …  ← usageHistory.records
   └─ Claude Desktop    74,422 tokens · Vs Oct 3 …  ← usageHistory.otherApps[0]
```

## What is wrong with a Local File data source

PR #446 makes `buddy-tokens.json` a `localFile` data source in `claude.json`.
The code follows the JSON design, but the model breaks the user's picture of the card:

| Evidence in the PR | What the user sees |
|---|---|
| `claude-buddy-tokens.js` returns `notes`, and `quotas` is empty "to keep the menu bar honest" | Picking Local File empties the menu bar and removes the session and weekly limits. The data source changed *what* is shown, not *how* it is fetched |
| `"fallback"` left out on purpose; the README adds "except Local File" | The only choice in the list that doesn't fall back, because it doesn't answer the same question |
| A Claude Code user in Local File mode | Two "tokens today" numbers in one card: the PR's note and Claude Code's Token Usage card |
| The data source is "for all Claude accounts"; the PR's design.md says "an added account shares it" | Every added login shows Desktop's 74,422 as its own |
| `ClaudeProbeMode.localFile`, `ClaudeProbeModeTests`, `setClaudeProbeMode(.localFile)` | Grows a vendor-named Swift enum that the settings view no longer reads (it lists `definition.dataSources`) |

Each exception (no fallback, no quotas, "except Local File") is there to make the
file fit somewhere it doesn't belong. The file is a usage history, so it goes
where usage histories go.

---

## 1 · Ubiquitous language

| Term | Meaning | Not to be confused with |
|---|---|---|
| **Usage history** | What one login used, day by day, read from its tool's logs on this Mac (*exists*: `UsageHistory`) | a **limit**: nothing in it is left or judged |
| **Other app** | Another app on this Mac that uses the same plan and keeps its own count, such as Claude Desktop. Declared as `usageHistory.otherApps[]` | a **data source**: an other app never answers "how much is left" and never replaces CLI or API |
| **Usual login** | The provider's default login, the one ClaudeBar finds without being told (*exists*: `Account.isDefault`) | an **added login**, which reads its own folder |
| **Today / Vs** | The local calendar day, compared with the day before (*exists*: `DailyUsageReport`) | the 5-hour **session** window |
| **Closed day** | A day kept in the ledger once it is over (*exists*: `DayLedger`) | a day still being read from the file |

The key is `otherApps`, not `apps` or `localApps`, because the login's own logs
are an app too (Claude Code). "Other" says these are the apps besides the one
this history is about.

## 2 · The aggregate, from the root down

```
Provider "claude"
└─ Account (usual login)                    isDefault; the only one with other apps
   └─ usageHistory: UsageHistory            this login's tool (Claude Code): days, ledger, knowsCost   [exists]
      └─ otherApps: [UsageHistory]          one per definition entry, in definition order               [new]
         └─ UsageHistory "Claude Desktop"   its own log, ledger and label; no prices, so knowsCost is false
            ├─ label                        the card's name, from the definition
            ├─ log: UsageLog                the entry's `records`: format json, `tokens.total`          [exists]
            └─ ledger: DayLedger            keyed "<login>/<label>", apart from the login's own days
                                            (the login's own fingerprint ignores otherApps, so no kept day re-sums)
Account (added login)
└─ usageHistory                             the patch sets otherApps to null, so it has none
```

The definition follows the same tree:

```jsonc
// claude.json
"usageHistory": {
  "records":  { …Claude Code, unchanged… },
  "prices":   { "file": "claude-prices.json" },
  "freeWhen": { … },
  "sessionGap": 1800,
  "otherApps": [{
    "label": "Claude Desktop",
    "records": {
      "files":  "~/Library/Application Support/Claude/buddy-tokens.json",
      "format": "json",
      "at":     { "field": "$.tokens-today.date", "format": "yyyy-MM-dd" },
      "tokens": { "total": "$.tokens-today.tokens" }
    }
  }]
},
"accounts": { "patch": { "usageHistory": {
  "records":  { "files": "{{account.configDirectory}}/projects/**/*.jsonl" },
  "freeWhen": { … },
  "otherApps": null
} } }
```

An `otherApps` entry is a `UsageLog.Definition` plus a `label`. It has no
`otherApps` of its own: the nesting is one level deep.

## 3 · The tells

```swift
// Popover opens: the login reads its history, and that reads its other apps.
await account.usageHistory?.read()

// The view lays out cards and makes no decisions.
TwoColumnCardGrid(items: history.usedOtherApps, id: \.label) { app in
    if let report = app.report {
        DailyUsageCardView(metric: .tokens, report: report, delay: delay, title: app.label)
    }
}
```

Asks to avoid:
- `if account.isDefault { show Desktop }` in the view. The patch already decides
  which login has other apps.
- `if stat.date != today { hide }` anywhere. A record dated yesterday is
  yesterday's usage, and the day buckets already put it there.
- A `switch` on `"Claude Desktop"`. The label is data.

## 4 · Invariants: each law, one owner

| Law | Owner |
|---|---|
| A data source answers "how much is left"; an other app never appears in Claude Configuration | `ProviderDefinition`: `otherApps` lives under `usageHistory`, not `dataSources` |
| An other app shows on the usual login only | `claude.json`'s `accounts.patch`: `"otherApps": null` (merge patch, *exists*) |
| An other app's tokens are never added to the login's own totals | `UsageHistory`: each other app is its own history with its own report |
| Without prices, an app shows tokens and no cost | `UsageLog.knowsCost` (*exists*) |
| A count is on the day its file names, in the user's time zone | `UsageLog.At`: a field read with a `format`, local unless `timeZone` says otherwise (§Rich types) |
| A token count is a whole, non-negative number; anything else drops the record | `RecordShape.record(from:)` |
| No card when the app has been used neither today nor yesterday (a missing file included) | `UsageHistory.read`: `report` is nil when both days are empty (*exists*) |
| A closed day is kept once and never read again | `DayLedger`, under a key apart from the login's (*exists*, new key) |

## Rich types: `UsageLog.At`, a field with a format

> **Pointable as:** the date written in the app's own file.

| | |
|---|---|
| **Owns** | how a written date becomes a day: ISO 8601 text or epoch seconds (*exists*), a path (*exists*), or a field with a `format` (new) |
| **It answers** | `Date?` for a record. `nil` drops the record, as today |
| **Never** | Guesses a format. `"2026-05-28"` goes through `ISO8601Instant` today, which needs a time, so the record is dropped. The definition has to say `"format": "yyyy-MM-dd"` |

Decoding: a string is `.field` (*exists*); an object with `fromPath` is `.fromPath`
(*exists*); an object with `field` and `format` is `.formatted` (new). It shares
`FromPath`'s `format` and `timeZone` meaning, and nil means `TimeZone.current`.

## What dies

When PR #446 is reworked onto this design:
- the `localFile` data source in `claude.json`, and `claude-buddy-tokens.js`
- `ClaudeProbeMode.localFile`, `ClaudeProbeModeTests.swift`, and the `setClaudeProbeMode(.localFile)` tests
- the "except Local File" sentence in `providers/claude/README.md` and the "Local File mode" section of its `design.md`

Its fixtures carry over as `UsageLog` tests: current, yesterday's, a future date,
an impossible date (`2026-02-30`), a missing field, a negative or fractional count,
and malformed JSON.

## Build sequence

Each slice is test-first and green before the next.

1. **`At` reads a field with a format.** `DataSources` tests: `"2026-05-28"` with
   `yyyy-MM-dd` is that day's local midnight in UTC−7 and UTC+8; `2026-02-30`
   drops the record; the existing `.field` and `.fromPath` forms decode unchanged.
2. **A `json` file with `tokens.total` is one day's record.** `UsageLog` on a
   buddy-tokens fixture: today is 74,422 tokens; a file dated yesterday gives
   today 0 and yesterday 74,422; a negative, fractional or missing count drops
   the record; `knowsCost` is false.
3. **`otherApps` in the definition.** `UsageLog.Definition` decodes and encodes
   `otherApps`; an entry has a `label`. The patch with `"otherApps": null`
   removes it (`usageHistory(forAccount:)`).
4. **`UsageHistory.otherApps`.** `Providers.history` makes one `UsageHistory` per
   entry with ledger key `<login>/<label>`. `read()` reads them. The usual login
   has Claude Desktop; an added login has none.
5. **`claude.json`.** Add the entry and the patch line. `ClaudeTests` pin both
   against the real definition.
6. **The popover.** One tokens card per other app with a report, titled by its
   label, after the login's own Today cards and behind the same Daily Usage
   Cards switch. The 30-day chart stays the login's own.
7. **Today without limits.** The Today section shows when the provider has no
   snapshot because its data source failed. Without this, the #198 user, who has
   no CLI, still sees only an error. See open question 1.
8. **Docs.** A row in [README.md](README.md)'s *Reads* table; the Claude README
   says Desktop's tokens appear under Today; one CHANGELOG line.

## 5 · Open questions

1. **What the limits area says without Claude Code.** Today it shows "Claude CLI
   not found" or "No OAuth credentials found". The mockup proposes "See your
   session and weekly limits. ClaudeBar reads your plan's limits through Claude
   Code" with a *Set up Claude Code* button. This belongs to the error
   presentation, not this doc. Add Account's *Sign in with browser* runs
   `claude auth login`, so it needs the CLI too and can't be the way in.
2. **Today 0, yesterday not.** `DailyUsageCardView` would show "0". The mockup
   says "Not used yet today". Decide whether that wording belongs to the card for
   every provider, or nowhere.
3. **Yesterday can be lost.** The file holds only today. A day is closed an hour
   after it ends; if Desktop is used before then, the file already holds the new
   day and yesterday reads 0. Accept this, or keep the last value read for a day
   that isn't closed yet?
4. **A switch per app.** Daily Usage Cards turns every card off. Is a
   per-app switch needed (the QUOTAS card pattern)? Not in the first slices.
5. ~~**A new top-level key (`localApps`) or inside `usageHistory`?**~~ Inside
   `usageHistory`. The added-login merge patch can then remove it with `null`,
   with no new rule, and the definition says that an app's usage is usage history.
6. ~~**One record list, merged into the login's totals?**~~ No. Desktop's file has
   no model, so the price list would charge it at Sonnet rates and invent a cost,
   and the Claude Code card would no longer mean Claude Code.
