# Security Policy

ClaudeBar reads your AI coding quotas with the CLIs, tokens and sign-ins already on your Mac, so a flaw in how it finds, stores or sends a credential matters. Thank you for reporting one privately.

## Supported versions

Only the latest release gets security fixes. Sparkle updates the app for you; check under **Settings → Updates**.

## Reporting a vulnerability

**Don't open a public issue.** Report it privately on GitHub: [**Report a vulnerability**](https://github.com/tddworks/ClaudeBar/security/advisories/new) (the Security tab → *Advisories*).

Please include:

- what an attacker can do, and what they need first (local access, a malicious extension, a crafted API response, …)
- the ClaudeBar version and macOS version
- steps or a proof of concept that reproduce it

Leave out real tokens, keys, cookies or usage data. Redact them in logs and screenshots.

## What to expect

- A first reply within 7 days.
- A fix in a release, credited to you in the advisory and the [CHANGELOG](CHANGELOG.md) unless you'd rather stay anonymous.
- The advisory is published once a fixed version is out.

## Scope

In scope: the ClaudeBar app, its provider definitions, how it handles credentials and settings (`~/.claudebar/`), its update feed and its release builds.

Out of scope: flaws in the providers' own services or CLIs (report those to the vendor), and extensions you install yourself from `~/.claudebar/extensions/`, which run with your user's permissions by design.
