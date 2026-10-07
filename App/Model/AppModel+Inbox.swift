import Foundation
import PrefillKit

// One thing Prefill added or wants to add: a value typed on a form, an answer learned from
// an application, or a value the person picked on a site, which Prefill now offers first there.
enum InboxEntry: Identifiable, Hashable {
    case capture(RecentItem)
    case learned(LearnedAnswer, CustomField)
    case picked(FirstPick)

    var id: String {
        switch self {
        case .capture(let item): "capture-\(item.id)"
        case .learned(let answer, _): "learned-\(answer.id)"
        case .picked(let pick): "picked-\(pick.value.id)-\(pick.site)"
        }
    }

    var date: Date {
        switch self {
        case .capture(let item): item.date
        case .learned(let answer, _): answer.date
        case .picked(let pick): pick.date
        }
    }
}

struct FirstPick: Hashable {
    let value: ContactValue
    let site: String
    let date: Date
}

extension AppModel {
    // Values Prefill wasn't sure about, waiting for Add or Dismiss.
    var needsYou: [RecentItem] {
        recent.filter { $0.state == .waiting }
    }

    // Everything else Prefill did lately, newest first.
    var recently: [InboxEntry] {
        let captures = recent.filter { $0.state != .waiting }.map(InboxEntry.capture)
        let learned = learnedAnswers.compactMap { answer in
            customFields.first(where: answer.matches).map { InboxEntry.learned(answer, $0) }
        }
        return (captures + learned + firstPicks.map(InboxEntry.picked)).sorted { $0.date > $1.date }
    }

    // Picks from Prefill's list or Safari's sheet that still decide a site's first value,
    // each site and kind once at its latest pick.
    var firstPicks: [FirstPick] {
        let byID = Dictionary(ContactKind.allCases.flatMap(values).map { ($0.id, $0) }) { first, _ in first }
        var seen = Set<String>()
        return events.pins.reversed().compactMap { pin in
            let site = Normalizer.registrableDomain(pin.host)
            guard seen.insert("\(pin.kind.rawValue) \(site)").inserted, let id = pin.valueID,
                  state.pinnedValue(pin.kind, on: site) == id, let value = byID[id] else { return nil }
            return FirstPick(value: value, site: site, date: pin.date)
        }
    }
}
