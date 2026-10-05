---
description: JetBrains AI's JSON definition — the newest quota file across every IDE through Paths, and how jetbrains-quota.js reads the JSON inside the IDE's XML.
---

# JetBrains AI as a definition

`jetbrains.json` reads one file, the newest of every IDE's, through `Paths` ([ENGINE_DESIGN §2.9](../../architecture/ENGINE_DESIGN.md#29--what-a-new-provider-still-cant-say)).

```text
file.path  ["~/Library/Application Support/JetBrains/*/options/AIAssistantQuotaManager2.xml",
            "~/Library/Application Support/Google/*/options/AIAssistantQuotaManager2.xml"]
        ▼   the most recently changed match
jetbrains-quota.js
  <option name="quotaInfo" value="{…HTML-encoded JSON…}">
    type Unknown → sessionExpired "Sign in to JetBrains AI in your IDE, then use AI Assistant once."
    type Error   → executionFailed "Your JetBrains IDE couldn't get the AI quota …"
    current / maximum (text numbers) → time "AI credits", percent left
  <option name="nextRefill" value="{…}">
    next → resetsAt · tariff.duration (PT720H) → window
```

The file is plain XML whose attribute values hold JSON with `&quot;` and `&#10;`; the script decodes those entities and parses the JSON. `tariffQuota.available` and `until` are not shown. A Mac with no IDE that saved a quota has no file, so the source is not *Configured*. The connection names no host and runs nothing.
