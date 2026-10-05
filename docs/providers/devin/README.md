---
description: Track your Devin organization's daily and weekly quota with your app.devin.ai sign-in from the browser, or a pasted session token. Use when setting up Devin or when its sign-in stops working.
---

# Devin

Shows how much of your Devin organization's daily and weekly quota is left and when each resets, your plan, and any extra-usage balance.

## Setup

1. Sign in to [app.devin.ai](https://app.devin.ai) in Chrome, Arc, Brave, Edge or another Chromium browser, and open your organization once.
2. Settings → Providers → Devin: turn it on. It's **off by default**. ClaudeBar reads your sign-in from the browser; there's nothing to paste.

ClaudeBar looks in this order: the browser's sign-in for app.devin.ai, then `DEVIN_BEARER_TOKEN`, then a pasted token. To paste one (Safari or Firefox, or a second organization), open the browser's developer tools → **Network** on app.devin.ai and copy from a request to `app.devin.ai/api/…`:
- **Session token**: the `Authorization` header, without `Bearer ` (it usually starts with `auth1_`).
- **Organization ID**: the `x-cog-org-id` header (it starts with `org_` or `org-`).

## Multiple accounts

**Add Account** takes a pasted session token and organization ID; an added account never uses the browser's sign-in.

## Gotchas

- **"Sign in to app.devin.ai again, or paste a new session token."** Devin answered 401 or 403. Sessions expire; sign in again in the browser. A wrong pasted organization ID gives the same answer.
- **Several browser profiles signed in to Devin:** ClaudeBar uses the first profile, in browser order, that has a sign-in, and takes the organization from that same profile.
- **The daily quota is missing** when Devin hides it for your plan.

## See also

[troubleshooting](../../troubleshooting.md) · [design](design.md)
