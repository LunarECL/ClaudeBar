---
description: Track MiniMax M Plan (formerly Token Plan) usage left per model, with an API key, on the International (minimax.io) or China (minimaxi.com) platform. Use when setting up MiniMax or when it shows an auth or HTTP error.
---

# MiniMax

Shows your MiniMax M Plan quota: one row per model and window (the 5-hour interval and the weekly limit), with the percentage used and the time that window ends. M Plan replaced the Token Plan, which is no longer sold; a Token Plan you kept renewing reads the same way ([MiniMax's notice](https://platform.minimax.io/docs/m-plan/token-plan-notice)).

## Setup

1. Get your M Plan API key from the MiniMax platform ([platform.minimax.io/console/plan](https://platform.minimax.io/console/plan), or platform.minimaxi.com in China). It is a different key from a pay-as-you-go API key.
2. Settings → Providers → MiniMax → turn it on. It is off by default.
3. In **Settings**:
   - **Region**: International (minimax.io) or China (minimaxi.com). **The default is China**, so international accounts must switch it.
   - **API Key**: paste the key and press **Save**. Check it with **Test Connection** in **MiniMax Configuration**.
4. A second MiniMax account: **Accounts → Add Account** asks for that account's own API key and region.

## Where the key comes from

The key is looked up in this order, as the card's **API KEY LOOKUP ORDER** note says:

1. An environment variable: `MINIMAX_API_KEY`, or the name you type in **Environment variable**.
2. The key saved in **API Key**.

The saved key is kept in your Keychain, never in `settings.json`; a key saved before this version moves there the first time it is read. An added account uses only its own saved key, never the environment variable.

## Gotchas

- **Check the region first when a valid key fails.** International and China are separate platforms with separate keys, and ClaudeBar only calls the one selected. The region was hard-wired to China before 0.4.38 ([#125](https://github.com/tddworks/ClaudeBar/issues/125)), and China is still the default.
- **The environment variable wins over the saved key.** If a `MINIMAX_API_KEY` in ClaudeBar's environment is stale, the key you pasted is never used.
- **Environment variables must be in ClaudeBar's own environment**, not just your shell's. Started from Finder, the Dock or Login Items, ClaudeBar doesn't see what `~/.zshrc` exports. Use the **API Key** field, or `launchctl setenv MINIMAX_API_KEY <key>` and restart ClaudeBar.
- **"MiniMax API error: …"** is MiniMax's own `status_msg`, passed through unchanged.
- **A video model's 5-hour row doesn't limit it.** On M Plan, video models (H3, on Explore and Build) count only against the weekly window; text, image and audio models need room in both ([usage rules](https://platform.minimax.io/docs/m-plan/usage-rules)).

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
