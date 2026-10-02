import Foundation
import PrefillKit

// Labels for new captures and kinds for new sites. The rules answer right away; the
// on-device model is asked, in one foreground batch per launch, only where they can't tell,
// and its answers are cached in AppState so the next launch and the Safari handler reuse them.
extension AppModel {
    // The label Recently added preselects for a capture the person hasn't labeled.
    func suggestedLabel(_ item: RecentItem) -> Insight<SuggestedLabel> {
        let key = InsightKey.label(item.value, host: item.host, variant: Intelligence.modelVariant)
        if let cached = state.insight(key).flatMap(SuggestedLabel.init(rawValue:)) {
            return Insight(cached, source: .model)
        }
        let guess = LabelRules.suggest(item.value, host: item.host, emailDomains: workDomains)
        return Insight(guess.label, source: .rules)
    }

    func refreshInsights() async {
        guard intelligenceState == .available, !isAskingModel else { return }
        let items = unlabeledItems
        let hosts = unplacedHosts
        guard !items.isEmpty || !hosts.isEmpty else { return }
        isAskingModel = true
        defer { isAskingModel = false }
        await intelligence.prewarm()
        let labels = await askLabels(items)
        let (siteAnswers, kinds) = await askSiteKinds(hosts)
        guard !labels.isEmpty || !siteAnswers.isEmpty else { return }
        commit(state.recording(labels + siteAnswers, siteKinds: kinds))
    }

    private var workDomains: Set<String> { SiteSense.workDomains(state.values) }

    private var unlabeledItems: [RecentItem] {
        recent.filter { item in
            item.state != .saved && item.value.label == nil
                && !LabelRules.suggest(item.value, host: item.host, emailDomains: workDomains).isSettled
                && suggestedLabel(item).source == .rules
        }
    }

    private var unplacedHosts: [String] {
        let variant = Intelligence.modelVariant
        return sites.map(\.host).filter { host in
            SiteSense.rules(host: host, emailDomains: workDomains) == .unknown
                && state.insight(InsightKey.siteKind(host, variant: variant)) == nil
        }
    }

    private func askLabels(_ items: [RecentItem]) async -> [CachedInsight] {
        var answers: [CachedInsight] = []
        for item in items {
            let answer = await intelligence.labelValue(item.value, host: item.host, emailDomains: workDomains)
            guard answer.source == .model else { continue }
            let key = InsightKey.label(item.value, host: item.host, variant: Intelligence.modelVariant)
            answers.append(CachedInsight(key: key, answer: answer.result.rawValue))
        }
        return answers
    }

    private func askSiteKinds(_ hosts: [String]) async -> ([CachedInsight], [String: SiteKind]) {
        var answers: [CachedInsight] = []
        var kinds: [String: SiteKind] = [:]
        for host in hosts {
            let answer = await intelligence.siteKind(host: host, emailDomains: workDomains)
            guard answer.source == .model else { continue }
            answers.append(CachedInsight(key: InsightKey.siteKind(host, variant: Intelligence.modelVariant),
                                         answer: answer.result.rawValue))
            kinds[Normalizer.registrableDomain(host)] = answer.result
        }
        return (answers, kinds)
    }
}
