import Foundation

// Sponsorship and work authorization answers are usually opposite ("No" and "Yes"), so a
// question must clearly be one of them before either answer fills it. Mirrored in
// web/src/workQuestion.ts.
enum WorkQuestion: Equatable {
    case authorization, sponsorship, both

    // "require sponsorship", "visa sponsorship", "H-1B".
    nonisolated(unsafe) private static let sponsorWords = /(?i)sponsor|\bh-?1b\b|\bvisa\b/
    // "Are you authorized to work", "legally eligible", "the right to work". "Sponsorship for
    // work authorization" asks about sponsorship, so "work authorization" alone doesn't count.
    nonisolated(unsafe) private static let authorizedWords: [Regex<Substring>] = [
        /(?i)\b(?:authori[sz]ed|eligible|permitted|entitled|able)\s+to\s+work\b/,
        /(?i)\bright to work\b|\blegally (?:authori[sz]ed|eligible|permitted)\b/
    ]

    init?(asking text: String) {
        let sponsor = text.contains(Self.sponsorWords)
        let authorized = Self.authorizedWords.contains { text.contains($0) }
        switch (sponsor, authorized) {
        case (true, true): self = .both
        case (true, false): self = .sponsorship
        case (false, true): self = .authorization
        case (false, false): return nil
        }
    }

    // Whether an answer to `question` may answer `text`: Sponsorship only a sponsorship
    // question, Work authorization only one without sponsorship words, neither one that asks both.
    static func fits(_ question: JobQuestion, _ text: String) -> Bool {
        let asked = WorkQuestion(asking: text)
        switch question {
        case .sponsorship: return asked == .sponsorship
        case .authorization: return asked != .sponsorship && asked != .both
        default: return true
        }
    }

    // "Do you have US work authorization?", "Are you a US citizen?": words that put a question
    // about authorization, where the stricter `authorizedWords` don't.
    nonisolated(unsafe) private static let workWords =
        /(?i)\bwork (?:authori[sz]ation|permit)|authori[sz]ation to work|\bcitizen|permanent resident|green card/

    // Whether the on-device model's pick of `question`'s answer may stand for `text`. The model
    // reads "Yes, I have US work authorization" as the answer to any yes/no question, so these
    // answers are guessed only for a question that is plainly about them.
    static func guessFits(_ question: JobQuestion, _ text: String) -> Bool {
        let asked = WorkQuestion(asking: text)
        switch question {
        case .sponsorship: return asked == .sponsorship
        case .authorization: return asked == .authorization || (asked == nil && text.contains(workWords))
        default: return true
        }
    }
}
