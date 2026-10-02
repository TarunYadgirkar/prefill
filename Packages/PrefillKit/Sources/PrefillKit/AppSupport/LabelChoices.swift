import Contacts

// Labels as Safari's bar captions them: system labels in Contacts' own lowercase wording,
// custom labels exactly as typed, and the kind's generic word for an unlabeled value.
public enum LabelChoices {
    public static func caption(_ label: String?, kind: ContactKind) -> String {
        guard let label, !label.isEmpty else { return unlabeled[kind] ?? kind.rawValue }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    // The system labels offered when relabeling, in the order Contacts lists them.
    public static func system(for kind: ContactKind) -> [String] {
        switch kind {
        case .email: [CNLabelHome, CNLabelWork, CNLabelSchool, CNLabelEmailiCloud, CNLabelOther]
        case .phone:
            [
                CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone, CNLabelHome, CNLabelWork,
                CNLabelSchool, CNLabelPhoneNumberMain, CNLabelOther
            ]
        case .address: [CNLabelHome, CNLabelWork, CNLabelSchool, CNLabelOther]
        }
    }

    public static func isSystem(_ label: String?, kind: ContactKind) -> Bool {
        label.map(system(for: kind).contains) ?? false
    }

    private static let unlabeled: [ContactKind: String] = [.email: "email", .phone: "phone", .address: "address"]
}
