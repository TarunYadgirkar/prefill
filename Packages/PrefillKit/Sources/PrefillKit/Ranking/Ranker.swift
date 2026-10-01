import Foundation

public enum SectionHint: String, Codable, Sendable, CaseIterable {
    case home, work, shipping, billing
}

public struct RankingContext: Sendable {
    public let host: String?
    public let hint: SectionHint?
    public let now: Date
    public let matchEachSite: Bool

    public init(host: String?, hint: SectionHint?, now: Date, matchEachSite: Bool) {
        self.host = host.map(Normalizer.registrableDomain)
        self.hint = hint
        self.now = now
        self.matchEachSite = matchEachSite
    }

    var isSiteSpecific: Bool { matchEachSite && host != nil }
}

public enum Ranker {
    static let recencyWeight = 0.5
    static let recencyHalfLife: TimeInterval = 14 * 86_400

    private enum Tier: Int, Comparable {
        case pinned, usedHere, hintLabel, hintRelated, other

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct Score: Comparable {
        let tier: Tier
        let strength: Double
        let manualIndex: Int

        static func < (lhs: Score, rhs: Score) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.strength != rhs.strength { return lhs.strength > rhs.strength }
            return lhs.manualIndex < rhs.manualIndex
        }
    }

    public static func rank(
        _ values: [ContactValue], usage: [UsageEvent], pins: [SitePin], context: RankingContext
    ) -> [ContactValue] {
        let signals = Signals(values: values, usage: usage, pins: pins, context: context)
        return values.enumerated()
            .map { index, value in (value, score(value, index: index, signals: signals)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private static func score(_ value: ContactValue, index: Int, signals: Signals) -> Score {
        let global = signals.globalScore(value, index: index)
        let tier = signals.tier(value)
        let strength = tier == .usedHere ? signals.lastUseHere[value.id]?.timeIntervalSince1970 ?? 0 : global
        return Score(tier: tier, strength: strength, manualIndex: index)
    }

    private struct Signals {
        let context: RankingContext
        let count: Int
        let pinned: UUID?
        let lastUseHere: [UUID: Date]
        let lastUseAnywhere: [UUID: Date]
        let workDomains: Set<String>

        init(values: [ContactValue], usage: [UsageEvent], pins: [SitePin], context: RankingContext) {
            self.context = context
            self.count = values.count
            let host = context.isSiteSpecific ? context.host : nil
            let kind = values.first?.kind
            self.pinned = pins.last { Normalizer.registrableDomain($0.host) == host && $0.kind == kind }?.valueID
            self.lastUseHere = Self.latest(usage.filter { Normalizer.registrableDomain($0.host) == host })
            self.lastUseAnywhere = Self.latest(usage)
            let workValues = values.filter { LabelName.of($0.label) == SectionHint.work.rawValue }
            self.workDomains = Set(workValues.compactMap(\.emailDomain))
        }

        func tier(_ value: ContactValue) -> Tier {
            guard context.isSiteSpecific else { return .other }
            if value.id == pinned { return .pinned }
            if lastUseHere[value.id] != nil { return .usedHere }
            return hintTier(value)
        }

        func globalScore(_ value: ContactValue, index: Int) -> Double {
            let manual = Double(count - index) / Double(count)
            guard let last = lastUseAnywhere[value.id] else { return manual }
            let age = max(0, context.now.timeIntervalSince(last))
            return manual + recencyWeight * pow(0.5, age / recencyHalfLife)
        }

        private func hintTier(_ value: ContactValue) -> Tier {
            guard let hint = context.hint else { return .other }
            let label = LabelName.of(value.label)
            if label == hint.rawValue { return .hintLabel }
            return isRelated(value, label: label, hint: hint) ? .hintRelated : .other
        }

        private func isRelated(_ value: ContactValue, label: String?, hint: SectionHint) -> Bool {
            switch hint {
            case .work: value.emailDomain.map(workDomains.contains) ?? false
            case .shipping, .billing: label == SectionHint.home.rawValue
            case .home: false
            }
        }

        private static func latest(_ events: [UsageEvent]) -> [UUID: Date] {
            events.reduce(into: [:]) { result, event in
                result[event.valueID] = max(result[event.valueID] ?? event.date, event.date)
            }
        }
    }
}

extension ContactValue {
    var emailDomain: String? {
        guard case .email(let address) = payload else { return nil }
        return Normalizer.emailDomain(address)
    }
}
