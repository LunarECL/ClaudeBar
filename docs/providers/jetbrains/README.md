---
description: Track your JetBrains AI credits for the month from the quota your JetBrains IDE (IntelliJ IDEA, PyCharm, Android Studio, …) saves on your Mac. Use when setting up JetBrains AI or when it asks you to sign in.
---

# JetBrains AI

Shows how much of this month's JetBrains AI credits are left and when they refill, from the IDE you used last: IntelliJ IDEA, PyCharm, WebStorm, GoLand, Rider, Android Studio, or any other JetBrains IDE.

## Setup

1. In your IDE, sign in to JetBrains AI and use AI Assistant once, so the IDE saves your quota.
2. Settings → Providers → JetBrains AI: turn it on. It's **off by default**. There's nothing to paste.

ClaudeBar reads `options/AIAssistantQuotaManager2.xml` under `~/Library/Application Support/JetBrains/<IDE>` (or `…/Google/<Android Studio>`), from the IDE whose file changed last. Nothing is sent anywhere.

## Gotchas

- **"Sign in to JetBrains AI in your IDE, then use AI Assistant once."** The IDE saved no quota: you aren't signed in to JetBrains AI there, or have no AI plan.
- **"Your JetBrains IDE couldn't get the AI quota …"** The IDE itself failed to fetch it. Open AI Assistant in the IDE to try again.
- **The numbers change when your IDE updates them,** not on their own. With several IDEs, the one you used last wins.
- **Not set up** means no JetBrains IDE on this Mac has saved a quota yet.

## See also

[troubleshooting](../../troubleshooting.md) · [design](design.md)
