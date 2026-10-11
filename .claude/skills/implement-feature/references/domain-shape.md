# Think the domain first

Every code change, a feature, an improvement or a bug fix, starts by asking how the domain should be, before asking where the code goes. The answer may be "as it is". It is still asked, because a change that only adds a line where it fits today grows the wrong shape one line at a time.

This page is the how. [domain-models.md](domain-models.md) has the basic patterns (behaviour over data, capabilities as handles, enums for states); the [design docs](../../../../docs/architecture/ARCHITECTURE.md) have the laws and their owners. The examples are from the leaderboard's devices ([#540](https://github.com/tddworks/ClaudeBar/pull/540)), where each of these was found in review.

## 1. From the root problem, not the code

Start from the person's problem (the issue, [USER_JOURNEYS](../../../../docs/architecture/USER_JOURNEYS.md)), not from the class you are about to edit. Write down the facts the domain must respect, then the concepts each fact forces:

| Fact (from #507) | Concept it forces |
|---|---|
| A person is one name on the board | **Member** |
| Usage is born on a machine; its logs hold only what ran there | **Device**: one machine, one key, so days add up instead of replacing each other |
| There are no accounts: a machine proves itself with a key it made | **Device request**: a new machine asks with a code |
| …and only a machine you already have can vouch for it | **Approval** by a member's device |
| Machines are sold, lost, copied, approved by mistake | **Removal**, the **first week**, the **copied key** |

Then compare with the code. A concept the facts force but the code doesn't have is usually hiding as optionals or a flag inside a neighbour. In #540 the device request lived inside `LeaderboardMembership` as `joining` plus three optionals, while the server already had it as its own table and route.

Words come from the person and the repo ([CANONICAL_MODEL](../../../../docs/architecture/CANONICAL_MODEL.md)), never from the mechanism.

## 2. The shape rules

Check every type the change touches against these. Each line is a smell, the question it raises, and the fix that #540 took.

| Rule | Smell | Fix (from #540) |
|---|---|---|
| **One aggregate per lifecycle** | Two states with no data in common share a class: one set of fields is `nil` while the other is used | A Mac asking to be added and a Mac that is a member never coexist, so `DeviceRequest` is its own aggregate beside `LeaderboardMembership` |
| **Mirror the other side's model** | The server (or the CLI, the file) has a concept the app folded into something else | `device_requests` on the server became `DeviceRequest` in the app |
| **Each aggregate changes only its own state** | A method on A reads B's internals and then sets B's state (`b.approval` … `b.markJoined()`) | B does it in one told call that changes B: `request.handOver()` answers what joining takes and moves the request to `joined` |
| **Tell, don't ask** | The caller reads state to decide what the owner could decide | The owner gets the method; the caller tells it |
| **Expose abilities, not rules** | A view could call a rule and decide for itself (`devices.isInFirstWeek(…)`) | Rules are `internal` to the module; the public surface is tells and the answers a view draws (`membership.removals(of:)`) |
| **Offer choices, don't take flags** | `remove(device:deletingDays: Bool)` after the caller asked `offersDeletingDays` | The owner answers the choices (`removals(of:) → [Removal]`) and takes one (`remove(_:_:)`), refusing what it didn't offer |
| **Invalid states can't be written** | An enum beside parallel optionals that can disagree with it; guards that unwrap them | The enum's cases carry their data (`.approved(member:summary:)`) |
| **Pointable types, primitives only at the edge** | `String` for a label, a key, an id inside the domain | `DeviceLabel`, `DeviceKey`; text only on the wire and in `settings.json` |
| **Values own their rules, tested directly** | A rule reachable only through another type's test, or a `private` helper | A value that answers it (`MemberDevices.isInFirstWeek(_:at:)`) with its own suite |
| **An object holds only what it uses** | A dependency kept only to pass on (`sleep` on the membership, for the request) | The user of it owns it, with its own default; tests build that object directly |
| **The boundary says exactly what the other side does** | Reading several forms "to be safe"; counting differently from the server | One form, from the other side's code (`toISOString()`); the server's count (UTF-16 units). Anything else fails, never guesses |

## 3. Refining the shape as you go

A change touches some types. Refine those, not the module:

- **In scope:** the types the change touches, and the smells above in them. Fix them in the same change, test first.
- **A new aggregate, a moved law, or a changed owner** is a design change: the tree, the law and its owner, the pieces table in the feature's `design.md` change first, and the person confirms them before code ([AGENTS.md](../../../../AGENTS.md#design-docs-are-the-source-of-truth)).
- **A module-wide pattern** you disagree with (in #540, the wire format as `Codable` on domain types) is noted, not changed: it is its own change.
- **Reviewing someone's PR:** the same rules, as questions in the review. If you do the refactor for them, offer it (a PR into their branch), don't push it onto theirs.

## 4. Draw it

Before code, draw the shape you are aiming at, now beside proposed, as ASCII. A diagram shows a missing aggregate or a reach into another one faster than prose:

```
 NOW                                     PROPOSED
 LeaderboardMembership                   DeviceRequest  (new Mac only)
  ├─ member stuff                         ├─ requestToJoin → waitForApproval
  └─ joining stuff ◀── both here          └─ handOver ──key + member──▶ LeaderboardMembership
                                                                         └─ member stuff only
```

## 5. Before showing the change

- [ ] Started from the root problem: the facts, and the concepts they force
- [ ] Every touched type checked against §2's rules
- [ ] Each aggregate changes only its own state; another is told, never set
- [ ] Public surface is tells and answers; rules are `internal`
- [ ] No Bool flag the caller decides; no parallel optionals beside an enum
- [ ] No `String` where a type names the thing, except at the wire and in storage
- [ ] Every rule has a direct test on its owner
- [ ] A design change went into `design.md` first, and was confirmed
