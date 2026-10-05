---
description: Track Warp's monthly AI credits and add-on credits with a Warp API key. Use when setting up Warp or when its key is rejected.
---

# Warp

Shows how many of this month's Warp AI credits you've used and when they refresh, plus any add-on credits granted to you or your workspaces and when the soonest of them expires. An unlimited plan shows as Unlimited.

## Setup

1. In Warp, open **Settings → Platform → API Keys** and create a key (it starts with `wk-`).
2. Settings → Providers → Warp: turn it on. It's **off by default**.
3. Paste the key into **API KEY**, then **Save & Test Connection**.

Instead of pasting, you can set `WARP_API_KEY` (or `WARP_TOKEN`) in ClaudeBar's environment.

## Multiple accounts

In Warp's **Accounts** card, choose **Add Account** and paste the other account's key.

## Gotchas

- **"Create a new API key in Warp …"** Warp refused the key (it reports this as `Unauthorized`). Create a new one.
- **"Warp: …"** is Warp's own error message, passed on as it came.
- **Add-on credits** add up what's granted to you and to each workspace you belong to.

## See also

[troubleshooting](../../troubleshooting.md) · [design](design.md)
