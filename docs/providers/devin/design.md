---
description: Devin's JSON definition — the browser's app.devin.ai sign-in through browserStorage, a pasted token after it, the quota request, and the two answer shapes devin-quota.js reads.
---

# Devin as a definition

`devin.json`: the browser's sign-in first, a pasted token after it, one HTTP request, one script.

```text
firstOf
  1. browserStorage https://app.devin.ai     token ← "*auth1_session" $.token
                                             organization ← "last-internal-org-for-external-org-v1-*"
  2. DEVIN_BEARER_TOKEN    + organization from setting.organization
  3. setting "token"       + organization from setting.organization
        ▼
GET https://app.devin.ai/api/{{organization}}/billing/quota/usage
Authorization: Bearer {{token}} · x-cog-org-id: {{organization}}
        ▼
devin-quota.js → time "Daily" · weekly · model "Extra usage" (USD balance) · plan
```

Each lookup brings its own values, so a browser token never goes with a pasted organization, and every browser value comes from one profile ([ENGINE_DESIGN §2.9](../../architecture/ENGINE_DESIGN.md#29--what-a-new-provider-still-cant-say)). An added login uses only its pasted token (`"firstOf": null`).

## Answer shapes

- Flat: `daily_percentage` / `weekly_percentage` with `daily_reset_at` / `weekly_reset_at`. A value below 1 is a fraction (0.12 → 12%). `hide_daily_quota: true` leaves the daily quota out.
- Nested: `quota_usage.daily_quota` / `weekly_quota` with `used`/`limit`, `remaining`/`limit`, `used_percent` or `remaining_percent`, and `reset_at` / `next_reset_at` (ISO 8601 or epoch seconds/milliseconds).
- `plan_name` (or `plan`, `tier`) becomes the plan badge, capitalised; `overage_balance` (or `overage_balance_cents`) the extra-usage balance.

Neither window is a mapping failure.
