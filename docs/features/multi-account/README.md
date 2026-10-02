---
description: Track separate Codex accounts by email, with independent usage cards and menu bar selections. Use when you have more than one ChatGPT login.
---

# Multiple accounts

Codex supports separate ChatGPT accounts. Each account appears with the Codex icon and its signed-in email, with independent quotas, refreshes, enable toggles and errors. Other providers retain their existing account behavior.

## Add a Codex account

1. Open **Settings → Providers → Codex → Codex Accounts → Add Codex Account**. If Codex already shows an email, select that entry instead.
2. Copy the provided login command and run it in Terminal. It creates a separate Codex folder and opens the normal Codex sign-in flow. Sign in to the account you want to add.
3. After sign-in completes, click **Choose Signed-in Folder** and select that folder. Its email is read automatically; no name or token needs to be pasted into ClaudeBar.

You can also choose an existing independently authenticated Codex folder. Additional accounts require file credential storage (`cli_auth_credentials_store = "file"`); the default account still supports Keychain through RPC mode.

The default login remains the one used by your ordinary Codex CLI. Added accounts use their own folders. Do not copy an existing `auth.json` to make a second login: authenticate separately so token refreshes have independent sessions.

## View both accounts

- Select either email in the dropdown's provider tabs.
- Enable **General → Overview Mode** to see all enabled accounts together.
- In **Menu Bar** settings, select both accounts to pin both quotas. Codex icons get email labels, with full addresses in the tooltip. Long labels shorten only when that still distinguishes the addresses. Accounts count toward the existing three-selection limit.

The Codex probe mode setting applies to all Codex accounts. Both RPC and API modes use each added account's own folder. Account-specific RPC failures never fall back to the default account's terminal session.

## Remove or reconnect

**Remove** only unlinks the account from ClaudeBar and its menu bar selections. It does not sign out of Codex or delete the folder.

For an expired session, sign in again using the same folder and account. If you sign in to a different account in that folder, ClaudeBar asks you to remove and re-add it rather than displaying the new account under the old email.

## See also

[Codex setup](../../providers/codex/README.md) · [Settings storage](../../settings.md) · [Design (contributors)](design.md)
