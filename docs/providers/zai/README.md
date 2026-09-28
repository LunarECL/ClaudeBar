---
description: Track the Z.ai / Zhipu GLM Coding Plan 5-hour, weekly and MCP quotas, read from Claude Code's settings. Use when setting up Z.ai or when it shows "Authentication required".
---

# Z.ai

Shows your GLM Coding Plan quota: the rolling 5-hour window, the weekly window, a monthly window on plans that have one, and MCP (tool) usage, each with its reset time. Token-based and credit-based plans (e.g. Coding Lite) both work.

## Setup

ClaudeBar doesn't ask for a Z.ai key. It reads the one you already gave Claude Code.

1. Install Claude Code, so `claude` is on your PATH. ClaudeBar checks for it even though it never runs it.
2. Point Claude Code at Z.ai in `~/.claude/settings.json`, as Z.ai's own setup guide does:
   ```json
   {
     "env": {
       "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
       "ANTHROPIC_AUTH_TOKEN": "<your Z.ai API key>"
     }
   }
   ```
   A base URL on `open.bigmodel.cn` (Zhipu, China) or `dev.bigmodel.cn` works too. ClaudeBar sends the quota request to the platform it finds there.
3. Settings → Providers → Z.ai. It is on by default.

## Where the key comes from

**Z.ai / GLM Configuration** in the provider's page is optional. The quickest route: paste your key into **API KEY** there and you're done. Otherwise ClaudeBar reads the one you already gave Claude Code.

- **API KEY**: paste your Z.ai key here and ClaudeBar uses it first. This works even when `~/.claude/settings.json` has no Z.ai URL in it — the quota request then goes to `api.z.ai`. The key is stored in the app's credential store and never logged.
- **SETTINGS.JSON PATH**: read a different file instead of `~/.claude/settings.json`. Type a full path such as `/Users/you/.claude/settings.json`; a leading `~` isn't expanded.
- **AUTH TOKEN ENV VAR (FALLBACK)**: the name of an environment variable (e.g. `GLM_AUTH_TOKEN`) to use when nothing earlier matches.

The key is looked up in this order: the **API KEY** saved in ClaudeBar settings, then `env.ANTHROPIC_AUTH_TOKEN` in the file, then `api_key` in a `providers` entry, then a top-level `api_key`, and only then the env var (the app's own environment first, then your login shell).

## Gotchas

- **The env var fallback now reads your login shell too.** ClaudeBar first looks in its own environment; if the variable isn't there it asks `$SHELL -l -c 'printf %s "$VAR"'`, so keys exported in `~/.zshrc` or `~/.bash_profile` are found even when the app starts from Finder, the Dock or Login Items ([#170](https://github.com/tddworks/ClaudeBar/issues/170)). `launchctl setenv` is no longer needed.
- **Only `ANTHROPIC_AUTH_TOKEN` is read from `env`.** A key stored as `ANTHROPIC_API_KEY` isn't found.
- **"Authentication required" also means no Z.ai URL was found** in the settings file. The file must contain `api.z.ai`, `open.bigmodel.cn` or `dev.bigmodel.cn` somewhere, and must be valid JSON.
- **No `claude` on PATH means no Z.ai**, even with a custom settings path.
- **Old versions:** before 0.4.61 the weekly window was merged into the 5-hour one, and before 0.4.75 credit-based plans failed with "No recognized quota types found". Update if you see either.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
