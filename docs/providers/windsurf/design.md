---
description: Windsurf's JSON definition — reading Windsurf's saved plan through the platform's read-only SQLite connection, the windsurf-plan.js mapping, the stale-plan rule, and why the web source waits.
---

# Windsurf as a definition

`windsurf.json` has one local data source: `fetch.sqlite` reads one row of Windsurf's own database, read-only, through `ReadOnlyQuery` ([ENGINE_DESIGN §2.9](../../architecture/ENGINE_DESIGN.md#29--what-a-new-provider-still-cant-say)).

```text
fetch.sqlite  {{platform.appData}}/Devin/User/globalStorage/state.vscdb
              {{platform.appData}}/Windsurf/User/globalStorage/state.vscdb   (the more recently changed one)
              SELECT value FROM ItemTable WHERE key = 'windsurf.settings.cachedPlanInfo' LIMIT 1
        ▼     [ { "value": "{…}" } ]   (a BLOB read as its UTF-8 or UTF-16LE text)
windsurf-plan.js
  no row → "Open Windsurf and sign in, so it saves your plan on this Mac."
  endTimestamp (ms) in the past → "saved plan is out of date"
  quotaUsage.daily/weeklyRemainingPercent + *ResetAtUnix → time "Daily" · weekly
  else usage.messages/flowActions (used or total − remaining) → model "Messages" · "Flow actions", resetting at endTimestamp
  planName → plan badge; nothing to measure → noData
```

**Devin Desktop.** Windsurf became Devin Desktop on 2026-06-02. Devin Desktop writes its per-user data to `Devin/` in the same app-data folder and only reads the legacy `Windsurf/` one; **Migrate from Windsurf** copies it once, **Start fresh** doesn't ([Devin Desktop FAQ](https://docs.devin.ai/desktop/devin-desktop-faq#what-local-file-paths-does-the-application-read-from-and-write-to)). The path lists both and the more recently changed database wins ([`Paths`](../../architecture/ENGINE_DESIGN.md#29--what-a-new-provider-still-cant-say)), so after migration the copy Windsurf left behind is never read, and someone still on Windsurf is read as before. The key is still `windsurf.settings.cachedPlanInfo`: Devin's docs don't name a new one, and no Devin database has been inspected yet.

The source is *Configured* only while the database is there, so a computer that never ran Windsurf shows it as not set up. Its connection names no host and runs nothing. The prefix keeps `~/Library/Application Support` on macOS and uses nonempty `APPDATA`, otherwise `~/AppData/Roaming`, on Windows. Windows SQLite and script mapping connections remain unavailable until the quotas phase.

## Not built yet

The web source, Windsurf's `GetPlanStatus` over ConnectRPC, sends a binary protobuf body; binary answers are their own later design (ENGINE_DESIGN §2.9).
