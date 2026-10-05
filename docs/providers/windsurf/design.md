---
description: Windsurf's JSON definition — reading Windsurf's saved plan with macOS's sqlite3, the windsurf-plan.js mapping, the stale-plan rule, and why the web source waits.
---

# Windsurf as a definition

`windsurf.json` has one local data source: `fetch.sqlite` reads one row of Windsurf's own database, read-only, through `ReadOnlyQuery` ([ENGINE_DESIGN §2.9](../../architecture/ENGINE_DESIGN.md#29--what-a-new-provider-still-cant-say)).

```text
fetch.sqlite  ~/Library/Application Support/Windsurf/User/globalStorage/state.vscdb
              SELECT value FROM ItemTable WHERE key = 'windsurf.settings.cachedPlanInfo' LIMIT 1
        ▼     [ { "value": "{…}" } ]   (a BLOB read as its UTF-8 or UTF-16LE text)
windsurf-plan.js
  no row → "Open Windsurf and sign in, so it saves your plan on this Mac."
  endTimestamp (ms) in the past → "saved plan is out of date"
  quotaUsage.daily/weeklyRemainingPercent + *ResetAtUnix → time "Daily" · weekly
  else usage.messages/flowActions (used or total − remaining) → model "Messages" · "Flow actions", resetting at endTimestamp
  planName → plan badge; nothing to measure → noData
```

The source is *Configured* only while the database is there, so a Mac that never ran Windsurf shows it as not set up. Its connection names no host and runs nothing.

## Not built yet

The web source, Windsurf's `GetPlanStatus` over ConnectRPC, sends a binary protobuf body; binary answers are their own later design (ENGINE_DESIGN §2.9).
