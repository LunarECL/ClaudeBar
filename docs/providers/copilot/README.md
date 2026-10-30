---
description: Track GitHub Copilot monthly AI credits through the GitHub Billing API or the Copilot internal API, using a personal access token. Use when setting up Copilot or when it shows no data on a Business or Enterprise plan.
---

# Copilot

Shows your GitHub Copilot AI credits for the current month as a Monthly quota. Since 1 June 2026 GitHub bills Copilot in AI credits (1 credit = $0.01) instead of premium requests. The allowance resets at 00:00 UTC on the 1st of each month.

## Setup

Copilot is **off by default**, because it needs a token.

1. Settings → Providers → Copilot: turn it on.
2. Signed in to the GitHub CLI (`gh auth login`)? That's enough: with no token saved, Copilot reads your AI credits through the Copilot API with `gh`'s login. macOS may ask once to let ClaudeBar read the `gh:github.com` Keychain item.
3. Otherwise pick the **Data fetching method** under **Copilot Configuration** (see below), create the token it needs and paste it into **GitHub Token**. On Billing, also fill in **GitHub Username** and pick your **Copilot Plan**.

## Data sources

| Data source | Needs | Pick it when |
|---|---|---|
| Billing API (default) | Fine-grained token with **Plan: read**, plus your GitHub username | Individual plans (Pro, Pro+, Max) |
| Copilot API | Classic token with the **copilot** scope, or the GitHub CLI's login | Free or Student, Business or Enterprise, or whenever Billing shows no usage |

Billing hands over to the Copilot API when it has no token or GitHub refuses it. Billing adds up the Copilot AI credits in this month's usage report and measures them against the allowance of the **Copilot Plan** you pick, because GitHub's report doesn't include one:

| Copilot Plan | Monthly allowance |
|---|---|
| Pro (default) | 1,500 AI credits |
| Pro+ | 7,000 AI credits |
| Max | 20,000 AI credits |
| Business | 1,900 AI credits per user |
| Enterprise | 3,900 AI credits per user |
| Pro, annual on premium requests | 300 premium requests |
| Pro+, annual on premium requests | 1,500 premium requests |

Pick an *annual on premium requests* plan only if you kept an annual Pro or Pro+ plan on GitHub's older request-based billing after 1 June 2026; Billing then reads GitHub's premium request report instead. GitHub doesn't publish the Free and Student allowances, so on those plans use the Copilot API. The Copilot API reads your allowance and remaining credits straight from GitHub, and shows your plan.

## More than one account

**Accounts → Add Account** asks for what the active data source needs: a token, plus a username and Copilot plan on Billing. An added account never reads the environment variable.

## Gotchas

- **Billing shows 0 used on an organization seat.** The Billing API has nothing to report for org-provided Business seats. Switch to the Copilot API, or fill in **Used This Month** with the number from GitHub, as a count (`99`) or a percentage (`198%`). It's used only while GitHub reports no usage, and isn't cleared for you when a new month starts.
- **"Authentication required" with a token saved** means GitHub refused it (expired or revoked). A saved token comes before the GitHub CLI's login, so **Clear** it to fall back to `gh`, or paste a new one.
- **Using an environment variable instead of pasting the token.** ClaudeBar reads `COPILOT_TOKEN`, or the name you put in **Environment variable**, before the pasted token. It reads ClaudeBar's own environment, so a variable exported only in your shell profile isn't visible when ClaudeBar starts from Finder or at login.
- **"Forbidden - ensure the token has 'Plan: read' permission"** (Billing) or **"Forbidden - ensure the classic token has the 'copilot' scope"** (Copilot API) means the token type doesn't match the data source. A fine-grained token doesn't work for the Copilot API.
- **"No Copilot subscription found"** (Copilot API, HTTP 404) means the token's account has no Copilot seat.
- **Unlimited, or no AI credits quota**, shows your plan and no card, rather than a 100% one.
- **Over the limit.** Billing lets the remaining percentage go negative, so you can see how far over you are.
- **The allowance looks wrong after updating.** ClaudeBar used to ask for a *Monthly AI Credits* number (default 50, from the premium request era). It now asks for your **Copilot Plan** instead and starts on Pro; pick your plan once.
- **Business and Enterprise credits are pooled** across the organization, so you can use more than your own 1,900 or 3,900 before GitHub stops you. Billing measures against the per-user figure.
- **The token lives in the Keychain** (moved there from app preferences the first time it's read).

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
