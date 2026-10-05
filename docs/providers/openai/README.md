---
description: Track your OpenAI API organization's spend for the last 30 days, per line item, with an organization Admin API key. Use when setting up OpenAI or when it asks for an Admin key.
---

# OpenAI API

Shows what your OpenAI API organization spent over the last 30 days, in dollars, with a line per item (text tokens, web search, …). It's spend, not a quota: there's no limit or reset.

## Setup

1. In the [OpenAI platform](https://platform.openai.com/settings/organization/admin-keys), create an **Admin key** (organization owners can). Ordinary project keys can't read spend.
2. Settings → Providers → OpenAI API: turn it on. It's **off by default**.
3. Paste the Admin key into **ADMIN API KEY**, then **Save & Test Connection**. Or set `OPENAI_ADMIN_KEY` in ClaudeBar's environment.

## Multiple accounts

**Add Account** takes another organization's Admin key; each added account uses only its own key.

## Gotchas

- **"Use an organization Admin API key; project keys can't read spend."** OpenAI answered 401 or 403: the key isn't an Admin key, or was revoked.
- **The 30 days are UTC days,** from midnight UTC 29 days ago through today.
- **ChatGPT subscriptions aren't here.** This is API spend; Codex shows ChatGPT plan limits.

## See also

[troubleshooting](../../troubleshooting.md) · [design](design.md)
