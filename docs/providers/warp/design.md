---
description: Warp's JSON definition — the GraphQL request it sends, the headers Warp's edge expects, and how warp-credits.js reads monthly and add-on credits.
---

# Warp as a definition

`warp.json` sends one GraphQL POST with an API key; `warp-credits.js` reads the answer.

```text
WARP_API_KEY → WARP_TOKEN → pasted key
        ▼
POST https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo
  User-Agent: Warp/1.0 · x-warp-client-id: warp-app · x-warp-os-*: macOS
  { operationName, query, variables.requestContext }
        ▼
requestLimitInfo → time "Monthly" (used/limit, nextRefreshTime; Unlimited)
bonusGrants + workspaces[].bonusGrantsInfo.grants → model "Add-on" (remaining/granted, soonest expiry)
```

## Gotchas

- Warp's edge answers **429 "Rate exceeded"** without `User-Agent: Warp/1.0`.
- A refused key comes back as **HTTP 200 with `errors: [{message: "Unauthorized"}]`**; the script turns that into `sessionExpired`, and any other message into `executionFailed("Warp: …")`.
- Numbers and booleans sometimes arrive as text (`"15"`, `"true"`).
- Warp's app also sends `x-warp-os-version`; ClaudeBar has no OS-version template, so it leaves the header out.
