---
description: Track Windsurf's daily and weekly quota, or its message and flow-action allowances, from the plan the Windsurf app saves on your Mac. Use when setting up Windsurf or when its numbers look old.
---

# Windsurf

Shows how much of your Windsurf daily and weekly quota is left and when each resets, with your plan. On plans without those quotas it shows your message and flow-action allowances for the billing period.

## Setup

1. Open the Windsurf app and sign in once.
2. Settings → Providers → Windsurf: turn it on. It's **off by default**. There's no key to paste.

ClaudeBar reads the plan Windsurf saves in `~/Library/Application Support/Windsurf/User/globalStorage/state.vscdb`, read-only. It runs nothing and sends nothing anywhere.

## Gotchas

- **The numbers only change while Windsurf runs.** Windsurf updates its saved plan itself; with Windsurf closed, ClaudeBar shows the last numbers it saved.
- **"Windsurf's saved plan is out of date. Open Windsurf to update it."** The saved plan's billing period has ended, so its numbers are old. Open Windsurf.
- **"Open Windsurf and sign in …"** Windsurf hasn't saved a plan yet. Until Windsurf has run once on this Mac, the card shows as not set up.
- **A free plan** has nothing to measure, so the card shows no data.

## See also

[troubleshooting](../../troubleshooting.md) · [design](design.md)
