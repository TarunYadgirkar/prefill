import Foundation

// "Used on": the sites an answer went into, newest first, each site once at its latest use.
// Fills, saves and picks of contact values and links leave UsageEvents, sheet picks leave
// PinEvents, and a custom field's answer counts where the person typed it on a form. A
// custom answer picked from Prefill's list isn't here: AnswerPick keeps no site.
extension Memory {
    public struct Use: Hashable, Sendable {
        public let site: String
        public let date: Date

        init(host: String, date: Date) {
            self.site = Normalizer.registrableDomain(host)
            self.date = date
        }
    }

    public func uses(of answer: Answer) -> [Use] {
        history[answer.id] ?? []
    }

    static func history(events: ExtensionEvents, fields: [CustomField]) -> [UUID: [Use]] {
        let usage = events.usage.map { ($0.valueID, Use(host: $0.host, date: $0.date)) }
        let pins = events.pins.compactMap { pin in pin.valueID.map { ($0, Use(host: pin.host, date: pin.date)) } }
        let learned = events.answers.compactMap { answer in
            fields.first(where: answer.matches).map { (Answer.customID($0), Use(host: answer.host, date: answer.date)) }
        }
        return Dictionary(grouping: usage + pins + learned, by: \.0).mapValues { latestPerSite($0.map(\.1)) }
    }

    private static func latestPerSite(_ uses: [Use]) -> [Use] {
        var seen = Set<String>()
        return uses.sorted { $0.date > $1.date }.filter { seen.insert($0.site).inserted }
    }
}
