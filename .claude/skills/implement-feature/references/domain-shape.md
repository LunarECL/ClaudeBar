# Think the domain first

Before any change, a fix too, ask how the domain should be, not only where the line fits. The aim is a domain that is **easy to understand**: someone new reads a type's public surface and can explain it in the person's words. We borrow from DDD only what serves that; no pattern is added for its own sake.

The Swift patterns are in [domain-models.md](domain-models.md); the laws and their owners in the [design docs](../../../../docs/architecture/ARCHITECTURE.md).

## Five questions

**1. Would the person say it?**
Names come from the screen and the person ([CANONICAL_MODEL](../../../../docs/architecture/CANONICAL_MODEL.md)), never from the mechanism. Start from their problem: if the facts need a concept the code doesn't have, it is hiding somewhere as optionals or a flag. *#540: a Mac asking to join lived inside the membership as `joining` plus three optionals; it became `DeviceRequest`.*

**2. Does the thing decide about itself?**
A rule lives on the thing it is about; callers tell it, they don't read its state and decide. *`QuotaAlerts.add(_:)` checks every rule and throws a `Refusal` Settings prints; `Setting.value(from:)` instead of `setting.default ?? options.first` at each caller.*

**3. Can you see every state?**
Each state the person can meet is a case, carrying its data; one value never means two things. *`UsageHistory.lastThirtyDays` is `nil` both before the first read and after thirty empty days, so the view couldn't tell "on its way" from "none" (#536).*

**4. Is it as small as it can be?**
A plain value when it is data with rules; a class only when it changes over time; a protocol only at the outside world (files, network, processes, Keychain), so tests can stub it. No type, layer or flag the change doesn't need. *`SignedInFolder.goesWithAccount` is a value answering one question, tested on its own.*

**5. Is what differs between providers data?**
A definition, or a handle that is `nil` when not declared; never a `switch` on an id or a vendor name in a module. *`account.usageHistory`, `provider.inUse`.*

## An example: the chart that came in late ([#536](https://github.com/tddworks/ClaudeBar/pull/536))

The bug: on the first open, *Daily usage — last 30 days* appeared after the rest of the popover, and a fix at the view removed its fade. Asking the five questions of `UsageHistory` finds the cause in the domain instead.

```swift
// NOW (Modules/Providers/Sources/UsageHistory.swift)
public private(set) var lastThirtyDays: Quotas.Days?      // nil: not read yet, OR read and empty

public func read() async {
    …
    lastThirtyDays = month.stats.allSatisfy(\.isEmpty) ? nil : month
}

// the view
if let lastThirtyDays { UsageHistoryChartView(days: lastThirtyDays) }   // arriving? or none?
```

| Question | What it finds |
|---|---|
| 1. Would the person say it? | Yes: *last 30 days* is the card's title. Keep the name |
| 2. Does the thing decide about itself? | No: `read()` reaches into `month.stats` to decide "empty". `Days` should answer `isEmpty` |
| 3. Can you see every state? | No: `nil` is two states the person meets, *still reading* and *nothing used* |
| 4. Is it as small as it can be? | A three-case enum is enough; no new type for the chart, no flag on the view |
| 5. Is what differs data? | Yes already: the definition's `usageHistory` says where the logs are |

```swift
// PROPOSED: the states the person meets, each one a case
public enum LastThirtyDays: Equatable { case notReadYet, nothingUsed, used(Quotas.Days) }
public private(set) var lastThirtyDays: LastThirtyDays = .notReadYet

lastThirtyDays = month.isEmpty ? .nothingUsed : .used(month)   // Days decides

// the view draws each state, and can fade in on .notReadYet → .used
if case .used(let days) = history.lastThirtyDays { UsageHistoryChartView(days: days) }
```

The proposed shape is small: one enum, one new property on `Days`, and the view draws each state instead of guessing. Since it changes what `UsageHistory` says, it goes into the [daily-usage design](../../../../docs/features/daily-usage/design.md) first.

## Keep it in scope

- Fix what these questions find **in the types the change touches**, test first. Leave the rest for its own change.
- A new aggregate, a moved law or a changed owner is a design change: `design.md` first, confirmed before code ([AGENTS.md](../../../../AGENTS.md#design-docs-are-the-source-of-truth)).
- When it isn't obvious, draw now beside proposed as a few lines of ASCII:

```
 NOW                                 PROPOSED
 LeaderboardMembership               DeviceRequest (new Mac only) ──handOver──▶ LeaderboardMembership
  ├─ member stuff                                                                 └─ member stuff only
  └─ joining stuff ◀── both here
```
