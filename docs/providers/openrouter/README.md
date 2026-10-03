---
description: Track your OpenRouter credit balance (total credits minus usage, in USD) with an OpenRouter API key. Use when setting up OpenRouter or when its key is rejected.
---

# OpenRouter

Shows your OpenRouter credit balance — total credits minus total usage, in USD. OpenRouter is pay-per-use, so there's no quota window or reset: the card shows the money left. When usage has overrun the balance, the card shows it as depleted.

## Setup

1. Create an API key at [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys) (the **Open OpenRouter API Keys** link in the card goes there).
2. Settings → Providers → OpenRouter: turn it on. It's **off by default**.
3. Click OpenRouter, paste the key into **API KEY** under **OpenRouter Configuration**, then **Save & Test Connection**.

Instead of pasting a key, you can put the name of an environment variable in **API KEY ENV VAR (ALTERNATIVE)** (default `OPENROUTER_API_KEY`). ClaudeBar checks the variable first and falls back to the saved key.

## Gotchas

- **"Failed: OpenRouter rejected the API key."** OpenRouter answered 401 or 403. Check you copied the whole `sk-or-...` key and that it belongs to the account you funded.
- **"Failed: No API key found"** means neither the environment variable nor a saved key was found.
- **The environment variable must be in ClaudeBar's own environment.** It's read from the app process, so a variable exported only in `~/.zshrc` isn't seen when ClaudeBar starts from Finder or at login. Pasting the key is the reliable option.
- **The card shows DEPLETED (0%)** when your usage has met or exceeded your credits, even though the remaining amount (which can go negative) is still the balance OpenRouter reports.
- **Credits are always shown in USD** — that's the only currency OpenRouter bills in.
- **The key is stored in UserDefaults, not the Keychain.** **Remove API Key** in the card deletes it.

## See also

[troubleshooting](../../troubleshooting.md)
