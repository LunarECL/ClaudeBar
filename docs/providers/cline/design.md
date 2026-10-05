---
description: Cline's JSON definition — the key lookup order across environment, pasted key and Cline's own login file, the WorkOS token scheme, and the plan-limits mapping.
---

# Cline as a definition

`cline.json` is plain data: one HTTP data source and a JSON mapping, no script and no Swift.

```text
CLINE_API_KEY → CLINEPASS_API_KEY → pasted key → ~/.cline/data/settings/providers.json
        │  (scheme "")                               │ auth.accessToken → scheme "workos:" unless it has it
        └────────────────────────────┬───────────────┘ apiKey / auth.apiKey → scheme ""
                                     ▼
GET https://api.cline.bot/api/v1/users/me/plan/usage-limits
Authorization: Bearer {{scheme}}{{token}}
                                     ▼
data.limits[type=five_hour] → session · weekly → weekly · monthly → time "Monthly"
```

## The WorkOS scheme

A `cline auth` login is a WorkOS access token, sent as `workos:<token>`; an API key is sent as it is. Each lookup adds a `scheme` value with `with`, and the header is `Bearer {{scheme}}{{token}}`. A saved token that already starts with `workos:` matches its own lookup first (`match: { "token": "^workos:" }`), so it is never marked twice. ClaudeBar never refreshes Cline's login; a 401 or 403 asks the person to run `cline auth` again.

## Mapping

Each `data.limits` entry has `type`, `percentUsed` and an optional ISO 8601 `resetsAt`. Types ClaudeBar doesn't know (`experimental_pool`) are skipped. No limits, or `success: false`, is a mapping failure: "Cline listed no plan limits".
