import Contacts

// Contacts stores system labels wrapped, as "_$!<Work>!$_", and custom labels as typed.
enum LabelName {
    private static let prefix = "_$!<"
    private static let suffix = ">!$_"
    private static let systemLabels: [SectionHint: String] = [.home: CNLabelHome, .work: CNLabelWork]

    static func system(for section: SectionHint) -> String? {
        systemLabels[section]
    }

    static func of(_ label: String?) -> String? {
        guard let label else { return nil }
        let isSystem = label.hasPrefix(prefix) && label.hasSuffix(suffix) && label.count >= prefix.count + suffix.count
        let core = isSystem ? String(label.dropFirst(prefix.count).dropLast(suffix.count)) : label
        return Normalizer.fold(core)
    }
}
