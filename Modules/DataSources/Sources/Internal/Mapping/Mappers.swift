import Diagnostics
import Domain
import Foundation

/// `json` — reads a JSON response by paths into today's `UsageSnapshot`.
struct JSONMapper: Reading {
    let mapping: JSONMapping
    let now: @Sendable () -> Date

    func read(_ response: Response, providerId: String) throws -> UsageSnapshot {
        guard let document = try? JSONSerialization.jsonObject(with: response.body) else {
            throw ProbeError.parseFailed("Response is not JSON")
        }
        let scope = JSONScope(root: document, headers: response.headers)

        var quotas = mapping.quotas.flatMap { self.quotas(for: $0, in: scope, providerId: providerId) }
        if quotas.isEmpty, let empty = mapping.whenEmpty {
            if let condition = empty.condition, scope.string(condition.path) == condition.equals {
                quotas = empty.quotas.flatMap { self.quotas(for: $0, in: scope, providerId: providerId) }
            } else if let reason = empty.otherwise {
                throw ProbeError.parseFailed(reason)
            }
        }

        // Nothing answering is not a failure unless `whenEmpty` says so: a
        // provider that has no usage yet reports none (*No usage data*).
        let cost = mapping.cost.flatMap { self.cost(for: $0, in: scope, providerId: providerId) }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: now(),
            accountTier: mapping.plan.flatMap { plan(for: $0, in: scope) },
            costUsage: cost
        )
    }

    // MARK: - Quotas

    private func quotas(for rule: QuotaRule, in scope: JSONScope, providerId: String) -> [UsageQuota] {
        let base = rule.at.map { scope.moved(to: scope.value($0)) } ?? scope
        guard let each = rule.each else {
            return quota(for: rule, named: rule.name?.text, in: base, providerId: providerId).map { [$0] } ?? []
        }

        var elements: [JSONScope] = []
        switch base.value(each) {
        case let array as [Any]:
            elements = array.map { base.moved(to: $0) }
        case let map as [String: Any]:
            elements = map.keys.sorted()
                .filter { !rule.skipKeys.contains($0) }
                .map { base.moved(to: map[$0], key: $0) }
        default:
            return []
        }

        return elements.flatMap { element -> [UsageQuota] in
            guard let name = self.name(rule.name, in: element), !name.isEmpty else { return [] }
            let windows = rule.windows.isEmpty ? [QuotaRule.WindowPick(at: "")] : rule.windows
            return windows.compactMap { pick in
                let windowScope = pick.at.isEmpty ? element : element.moved(to: element.value(pick.at))
                return quota(for: rule, named: name + pick.suffix, in: windowScope, providerId: providerId)
            }
        }
    }

    private func quota(for rule: QuotaRule, named name: String?, in scope: JSONScope, providerId: String) -> UsageQuota? {
        let left: Double
        if let used = first(rule.usedPercent, in: scope) {
            left = max(0, 100 - used)
        } else if let remaining = first(rule.leftPercent, in: scope) {
            left = remaining
        } else {
            return nil
        }

        let resetsAt = rule.resetsAt.lazy.compactMap { self.date($0, in: scope) }.first
        let windowDuration: TimeInterval? = switch rule.window {
        case .seconds(let path)?: scope.number(path)
        case .minutes(let path)?: scope.number(path).map { $0 * 60 }
        case nil: nil
        }

        guard let type = Self.quotaType(rule.kind, name: name) else { return nil }
        return UsageQuota(
            percentRemaining: left,
            quotaType: type,
            providerId: providerId,
            resetsAt: resetsAt,
            resetText: rule.resetText ?? resetsAt.map { Countdown.text(until: $0, now: now()) },
            windowDuration: windowDuration
        )
    }

    static func quotaType(_ kind: QuotaKind, name: String?) -> QuotaType? {
        switch kind {
        case .session: return .session
        case .weekly: return .weekly
        case .model: return name.map { .modelSpecific($0) }
        case .time: return name.map { .timeLimit($0) }
        }
    }

    private func name(_ rule: NameRule?, in scope: JSONScope) -> String? {
        guard let rule else { return nil }
        if let text = rule.text { return text }
        guard let raw = rule.firstOf.lazy.compactMap({ scope.string($0) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        for drop in rule.dropPrefixes where trimmed.lowercased().hasPrefix(drop.prefix.lowercased()) {
            let rest = String(trimmed.dropFirst(drop.prefix.count))
            guard !rest.isEmpty else { return trimmed }
            return drop.capitalize ? rest.prefix(1).uppercased() + rest.dropFirst() : rest
        }
        return trimmed
    }

    // MARK: - Values

    private func first(_ refs: [ValueRef], in scope: JSONScope) -> Double? {
        for ref in refs {
            switch ref {
            case .constant(let value): return value
            case .path(let path): if let value = scope.number(path) { return value }
            }
        }
        return nil
    }

    private func date(_ ref: ResetRef, in scope: JSONScope) -> Date? {
        switch ref {
        case .epochSeconds(let path):
            return scope.number(path).map { Date(timeIntervalSince1970: $0) }
        case .secondsFromNow(let path):
            return scope.number(path).map { now().addingTimeInterval($0) }
        case .iso8601(let path):
            return scope.string(path).flatMap(OAuth2Refresher.parseDate)
        }
    }

    private func plan(for rule: PlanRule, in scope: JSONScope) -> AccountTier? {
        guard let value = scope.string(rule.path), !value.isEmpty else { return nil }
        return .custom(rule.badges[value.lowercased()] ?? value.uppercased())
    }

    private func cost(for rule: CostRule, in scope: JSONScope, providerId: String) -> CostUsage? {
        let limit = first(rule.limit, in: scope)
        let used: Double
        if let spent = first(rule.used, in: scope) {
            used = spent
        } else if let remaining = first(rule.remaining, in: scope), let limit {
            used = max(0, min(limit, limit - remaining))
        } else {
            return nil
        }
        return CostUsage(
            totalCost: Decimal(used),
            budget: limit.map { Decimal($0) },
            apiDuration: 0,
            providerId: providerId,
            kind: rule.kind == .extraUsage ? .extraUsage : .apiCost,
            capturedAt: now()
        )
    }
}

/// `text` — reads a terminal screen: a known error phrase fails the read;
/// otherwise each quota's label and the percentage within a few lines of it.
struct TextMapper: Reading {
    let mapping: TextMapping
    let now: @Sendable () -> Date

    func read(_ response: Response, providerId: String) throws -> UsageSnapshot {
        let screen = Self.stripANSI(response.text)
        let lower = screen.lowercased()

        for rule in mapping.errors {
            let any = rule.contains.contains { lower.contains($0.lowercased()) }
            let all = rule.alsoContains.allSatisfy { lower.contains($0.lowercased()) }
            if any && all {
                AppLog.probes.error("\(providerId) screen reports: \(rule.contains.first ?? "an error")")
                throw rule.error.probeError
            }
        }

        let lines = screen.components(separatedBy: .newlines)
        let quotas = mapping.quotas.compactMap { pattern -> UsageQuota? in
            guard let type = JSONMapper.quotaType(pattern.kind, name: pattern.name) else { return nil }
            if let regex = pattern.leftPercent, let left = Self.percent(after: pattern.label, matching: regex, within: pattern.lookahead, in: lines) {
                return UsageQuota(percentRemaining: left, quotaType: type, providerId: providerId)
            }
            if let regex = pattern.usedPercent, let used = Self.percent(after: pattern.label, matching: regex, within: pattern.lookahead, in: lines) {
                return UsageQuota(percentRemaining: max(0, 100 - used), quotaType: type, providerId: providerId)
            }
            return nil
        }

        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed(mapping.whenEmpty ?? "Could not find usage limits")
        }
        return UsageSnapshot(providerId: providerId, quotas: quotas, capturedAt: now())
    }

    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#, with: "", options: .regularExpression)
    }

    static func percent(after label: String, matching pattern: String, within lookahead: Int, in lines: [String]) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let label = label.lowercased()
        for (index, line) in lines.enumerated() where line.lowercased().contains(label) {
            for candidate in lines[index..<min(lines.count, index + lookahead)] {
                let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                if let match = regex.firstMatch(in: candidate, range: range),
                   match.numberOfRanges >= 2,
                   let value = Range(match.range(at: 1), in: candidate),
                   let number = Double(candidate[value]) {
                    return number
                }
            }
        }
        return nil
    }
}

/// "Resets in 2d 5h 30m" — the countdown today's probes write as `resetText`.
enum Countdown {
    static func text(until date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Resets soon" }
        let days = Int(interval / 86400)
        let hours = Int(interval.truncatingRemainder(dividingBy: 86400) / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if days > 0 { return "Resets in \(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        if minutes > 0 { return "Resets in \(minutes)m" }
        return "Resets soon"
    }
}
