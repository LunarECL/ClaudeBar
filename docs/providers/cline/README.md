---
description: Track your Cline plan's five-hour, weekly and monthly limits with a Cline API key or the login `cline auth` saved. Use when setting up Cline or when its key is rejected.
---

# Cline

Shows the limits of your Cline plan: the five-hour session, the week and the month, each with how much is left and when it resets.

## Setup

1. Settings → Providers → Cline: turn it on. It's **off by default**.
2. If you use the Cline CLI and ran `cline auth`, there's nothing else to do: ClaudeBar reads that login from `~/.cline/data/settings/providers.json`, read-only.
3. Otherwise create an API key in the [Cline dashboard](https://app.cline.bot/dashboard), paste it into **API KEY**, then **Save & Test Connection**.

ClaudeBar looks for a key in this order: `CLINE_API_KEY`, `CLINEPASS_API_KEY`, the pasted key, then Cline's own login.

## Multiple accounts

In Cline's **Accounts** card, choose **Add Account** and paste the other account's API key. Each added account uses only its own key.

## Gotchas

- **"Run `cline auth` or paste a new API key."** Cline answered 401 or 403. ClaudeBar never renews Cline's login; run `cline auth` again, or paste a key.
- **"Cline listed no plan limits"** means your account has no plan with limits.
- **The environment variable must be in ClaudeBar's own environment.** A variable exported only in `~/.zshrc` isn't seen when ClaudeBar starts from Finder or at login.

## See also

[troubleshooting](../../troubleshooting.md) · [design](design.md)
