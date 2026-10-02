# MiniMax: probe design

Research notes for the MiniMax Token Plan probe, from the code, [#115](https://github.com/tddworks/ClaudeBar/pull/115), [#128](https://github.com/tddworks/ClaudeBar/pull/128) and [#266](https://github.com/tddworks/ClaudeBar/pull/266) (adapted in 2026-09).

## Source

`GET <api base>/v1/token_plan/remains` with `Authorization: Bearer <key>`.

| Region | API base | Platform (dashboard, keys) |
|---|---|---|
| International | `https://api.minimax.io` | `https://platform.minimax.io` |
| China | `https://api.minimaxi.com` | `https://platform.minimaxi.com` |

The probe originally called `/v1/api/openplatform/coding_plan/remains`. That endpoint predates the Token Plan: keys generated under a Token Plan (the only kind MiniMax issues now) return count totals of `0` there, so every model showed 0% remaining. The endpoint was switched to `token_plan/remains`, which works for both the legacy count shape and the Token Plan percentage shape.

The first version hard-coded the China host, so international keys failed ([#125](https://github.com/tddworks/ClaudeBar/issues/125)). The region picker was added in 0.4.38; China is still the default.

HTTP 401/403 → "Authentication required"; any other non-200 → "MiniMax API returned HTTP N".

## Response

Shape (values illustrative):

```json
{
  "base_resp": { "status_code": 0, "status_msg": "…" },
  "model_remains": [
    { "model_name": "…", "current_interval_total_count": 0,
      "current_interval_usage_count": 0,
      "current_interval_remaining_percent": 100,
      "current_weekly_remaining_percent": 98,
      "start_time": <epoch ms>, "end_time": <epoch ms>,
      "weekly_start_time": <epoch ms>, "weekly_end_time": <epoch ms> }
  ]
}
```

- `base_resp.status_code` ≠ 0 → "MiniMax API error: `<status_msg>`".
- Empty or missing `model_remains` → "No usage data available".
- One quota per model, labelled with `model_name`.
- Timestamps are epoch **milliseconds**. `remains_time` is decoded but unused.

### Token Plan percentages

Token Plan responses carry `current_interval_remaining_percent` and `current_weekly_remaining_percent` (0–100), and the count fields are `0`. The probe emits **one quota per window**: the interval (5h) quota keeps the `modelSpecific` identity from the count era, and the weekly quota is a `timeLimit("<model> Weekly")` row with the weekly percentage, `weekly_end_time` as `resetsAt` and the weekly span as `windowDuration`. Reset text is "N% used".

### Legacy count fallback

Older responses (and older coding-plan payloads) only expose counts, where — despite the name — `current_interval_usage_count` is what's **left**, not what's used. This was confirmed against the MiniMax dashboard: at "3% used" the API returned `usage_count=1459` of `total=1500`. The probe clamps it to `0…total`, shows `total − usage_count` as used, and `usage_count / total` as percent remaining, with reset text "used/total requests".

A model with `current_interval_total_count` 0 and no percentage fields says nothing about what is left, so it shows no 5-hour window rather than a made-up 0% (the "no fake 100%" law, CANONICAL §5). If no model reports anything, the refresh fails with no data.
