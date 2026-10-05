---
description: OpenAI API's JSON definition — the Admin API costs request with a start date from SystemValues, and how openai-costs.js adds the spend up exactly.
---

# OpenAI API as a definition

`openai.json` asks for 30 daily buckets from a start date the engine computes ([ENGINE_DESIGN §2.9](../../architecture/ENGINE_DESIGN.md#29--what-a-new-provider-still-cant-say)).

```text
OPENAI_ADMIN_KEY → pasted Admin key
        ▼
GET https://api.openai.com/v1/organization/costs
    ?start_time={{system.day-29.epoch}}&bucket_width=1d&limit=30&group_by=line_item
        ▼   (UTC midnight 29 days before the fetch's now)
openai-costs.js
  data[].results[].amount.value  (number or text, null skipped) → added exactly (decimalAdd)
  one line per line_item, largest first; no line_item → "API"
  → cost apiCost, resetText "Last 30 days", no limit
```

`limit=30` with `bucket_width=1d` fits the 30 days in one page, so paging isn't needed. `amount.currency` is always USD in practice and isn't converted. The usage-completions endpoint (tokens per model) and project scoping are not read yet. 401/403 ask for an organization Admin key; 429 uses the shared retry.
