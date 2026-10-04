---
description: Contributor design for In use — choosing which login new claude/codex sessions start with. The record file and the LoginsInUse port, Provider.inUse and its rules, NewSessions and the ShellLines port, the shell lines ShellSetup writes, Switch when low, and the notification and claudebar://use link. Read before touching In use, the shell setup or account switching.
---

# In use: design

User guide: [README.md](README.md). Mockup: `design-concept/in-use/index.html`.

**Status: BUILT.** Choosing (popover, Settings, `claudebar://use`), the one-time shell setup (zsh, bash, fish), the low suggestion and its notification, and opt-in *Switch when low*.

| For | Read |
|---|---|
| Logins, folders, `Account`, `Provider` | [multiple accounts](../multi-account/design.md) |
| `claudebar://` routing | [URL schemes](../url-schemes/README.md) |

## The one sentence

**New sessions of a CLI start on the login whose folder is recorded for it; ClaudeBar records it, the shell reads it, and nothing else moves.**

```
 popover / Settings / claudebar://use / notification button
        │ tell
        ▼
 NewSessions.use(login) ── lines not in the shell? ── waits ──▶ setUp() · setUpByHand() · cancel()
        │                                                       (ShellLines port → ShellSetup)
        ▼
 Account.useForNewSessions() → Provider.use(_) → LoginsInUse.use(folder) → ~/.claudebar/in-use/<provider>
                                                                                    │ read on every run
 $ claude  ── function in ~/.zshrc ──▶ CLAUDE_CONFIG_DIR=<folder> command claude ◀──┘
```

No token is copied: each login keeps its own Keychain item and refresh token. No traffic goes through ClaudeBar.

## 1 · Ubiquitous language

| Term | Meaning | Not to be confused with |
|---|---|---|
| **in use** | the login new terminal sessions of a CLI start with | the *default* login (the plain one the CLI uses on its own), the *selected* chip |
| **new terminal sessions** | the next `claude` / `codex` run from a shell with the lines | running sessions, Claude Desktop, IDE extensions |
| **the record** | `~/.claudebar/in-use/<provider>`: the folder, or empty for the plain login | settings.json (keeps no copy) |
| **the shell lines** | the block between `# >>> claudebar in-use >>>` markers, or fish's own file | the user's own aliases and exports |
| **worth switching** | the login in use is critical or out, and another has more left | *Switch when low* (acts, opt-in) |

## 2 · The aggregate

```
NewSessions (Domain)                        the choice and the lines that make it count
├── products: [Provider]                    only those that canChooseInUse
├── shell: LoginShell, isSetUp              the login shell; whether its file has the lines
├── waiting: Account?                       chosen before the lines existed
└── ShellLines (port) ← ShellSetup (Infrastructure)

Provider (Modules/Providers)
├── canChooseInUse                          definition names accounts.signIn + folder, and a record exists
├── loginsForNewSessions / offersInUse      the plain login + folder logins; more than one
├── terminalCommand                         signIn.cli + signIn.homeVariable
├── inUse / use(_)                          via LoginsInUse (port) ← DiskLoginsInUse
├── suggestedLogin                          worth switching
├── switchesWhenLow, switchBelow, mayPick   opt-in; generic per-provider settings
└── reviewInUse() → InUseNotice?            after a refresh: switched, or worth switching (once)

Account
└── isInUse · canBeInUse · useForNewSessions()
```

## 3 · The tells

```swift
newSessions.use(login)                   // popover menu, chip, Settings, link, notification
newSessions.setUp()                      // "Add to ~/.zshrc"
if product.offersInUse { InUseStrip(provider: product) }
if login.isInUse { terminal mark }
let notice = try provider.reviewInUse()  // QuotaMonitor, after each refresh → InUseAlert
```

Views never compare accounts, inspect folders or count logins.

## 4 · Invariants — each law, one owner

| Law | Owner |
|---|---|
| The login in use is one of the provider's logins that is a folder, or the plain login; nothing recorded, or a folder no login has, is the plain login | `Provider.inUse` |
| Only the folder is recorded, nowhere else | `LoginsInUse` / `DiskLoginsInUse` |
| Removing the login in use goes back to the plain login | `Provider.remove` |
| A login chosen before the lines exist waits; the plain login never waits | `NewSessions.use` |
| Turning off removes the lines and puts every CLI back on its plain login | `NewSessions.turnOff` |
| The lines are written once, replace an alias for the CLI, and removing takes out nothing else | `ShellSetup` |
| A login worth switching to is told once per low | `Provider.reviewInUse` |
| *Switch when low* is off until turned on, moves only to ticked logins with more left, and never touches running sessions | `Provider.switchIfLow` |
| `claudebar://use` takes exactly `provider` and `account`, each once | `URLSchemeAction` |

Changed by this feature: a folder ClaudeBar made by *Sign in with browser* was "ClaudeBar's, and nothing else uses it". Now the person's terminal may use it, through the record ([multiple accounts](../multi-account/design.md)).

## 5 · Open questions

- ~~Copy tokens into the default login's place?~~ **No.** Refresh tokens rotate, so two copies log one of them out.
- ~~Symlink a fixed folder to the login in use?~~ **No.** Claude names a folder's Keychain item from a hash of its path, so a symlinked path finds no login.
- ~~Proxy the CLIs' traffic and switch per request?~~ **No.** That breaks provider terms, routes prompts through ClaudeBar, and makes coding depend on a menu bar app.
- **API-key providers** (env variables, not folders): an env-variable version of the record and lines.
- **A shell that isn't zsh, bash or fish**: the lines can be copied and adapted by hand.
