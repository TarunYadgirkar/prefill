import Contacts
import ContactsUI
import UIKit

@MainActor
final class Probe: NSObject {
    static let shared = Probe()

    enum Action: String, CaseIterable {
        case status, request, dump, listAll, reorder, add, reset, picker, fetchId, saveId, promoteFresh, promoteTwoSaves
    }

    private let store = CNContactStore()
    private let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("probe.log")
    private let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]
    private var watching = false

    func log(_ message: String) {
        let line = "\(ISO8601DateFormatter.withMillis.string(from: Date())) [probe] \(message)\n"
        print(line, terminator: "")
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logURL)
        }
    }

    func startWatching() {
        guard !watching else { return }
        watching = true
        NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { note in
            let info = (note.userInfo ?? [:]).map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
            MainActor.assumeIsolated {
                Probe.shared.log("CNContactStoreDidChange \(info)")
                _ = Probe.shared.dumpAlex()
            }
        }
        log("watching CNContactStoreDidChange; status=\(statusName())")
    }

    func run(_ action: Action) async -> String {
        log("action \(action.rawValue) start; status=\(statusName())")
        let result: String
        switch action {
        case .status: result = statusName()
        case .request: result = await requestAccess()
        case .dump: result = dumpAlex()
        case .listAll: result = listAll()
        case .reorder: result = mutateAlex { $0.reordered(toFront: "alex.school@example.edu") }
        case .add: result = mutateAlex { $0.inserting("new.first@example.org", label: "Personal") }
        case .reset: result = mutateAlex { _ in Self.originalEmails }
        case .picker: result = presentPicker()
        case .fetchId: result = fetchById(UserDefaults.standard.string(forKey: "id") ?? "")
        case .saveId: result = saveById(UserDefaults.standard.string(forKey: "id") ?? "")
        case .promoteFresh: result = mutateAlex { $0.reordered(toFront: Self.targetValue).fresh() }
        case .promoteTwoSaves:
            let first = mutateAlex { _ in [] }
            log("two-save step 1: \(first)")
            result = mutateAlex { _ in Self.stash.reordered(toFront: Self.targetValue).fresh() }
        }
        log("action \(action.rawValue) result: \(result)")
        return "\(action.rawValue): \(result)"
    }

    private static var targetValue: String { UserDefaults.standard.string(forKey: "value") ?? "alex.school@example.edu" }
    private static var stash: [CNLabeledValue<NSString>] = []

    private static var originalEmails: [CNLabeledValue<NSString>] {
        [
            CNLabeledValue(label: CNLabelHome, value: "alex.rivera@example.com"),
            CNLabeledValue(label: CNLabelWork, value: "alex@work.example.org"),
            CNLabeledValue(label: nil, value: "alex.school@example.edu"),
        ]
    }

    private func statusName() -> String {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        case .limited: "limited"
        @unknown default: "unknown"
        }
    }

    private func requestAccess() async -> String {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            return "granted=\(granted) status=\(statusName())"
        } catch {
            return describe(error)
        }
    }

    private func findAlex() throws -> CNContact? {
        let predicate = CNContact.predicateForContacts(matchingName: "Alex Rivera")
        return try store.unifiedContacts(matching: predicate, keysToFetch: keys).first
    }

    @discardableResult
    func dumpAlex() -> String {
        do {
            guard let alex = try findAlex() else { return "Alex not visible" }
            return "Alex id=\(alex.identifier) " + Self.describe(alex)
        } catch {
            return describe(error)
        }
    }

    private func listAll() -> String {
        let request = CNContactFetchRequest(keysToFetch: keys)
        var names: [String] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                names.append("\(contact.givenName) \(contact.familyName) [\(contact.identifier)]")
            }
            return "count=\(names.count) " + names.joined(separator: "; ")
        } catch {
            return describe(error)
        }
    }

    private func mutateAlex(_ transform: ([CNLabeledValue<NSString>]) -> [CNLabeledValue<NSString>]) -> String {
        do {
            guard let alex = try findAlex() else { return "Alex not visible" }
            log("before: " + Self.describe(alex))
            let mutable = alex.mutableCopy() as! CNMutableContact
            if !alex.emailAddresses.isEmpty { Self.stash = alex.emailAddresses }
            mutable.emailAddresses = transform(alex.emailAddresses)
            return save(mutable, id: alex.identifier)
        } catch {
            return describe(error)
        }
    }

    private func save(_ contact: CNMutableContact, id: String) -> String {
        let request = CNSaveRequest()
        request.transactionAuthor = "prefill.probe"
        request.update(contact)
        do {
            try store.execute(request)
            log("saved OK at \(ISO8601DateFormatter.withMillis.string(from: Date()))")
            guard let fresh = try? store.unifiedContact(withIdentifier: id, keysToFetch: keys) else { return "saved; refetch failed" }
            return "saved; after: " + Self.describe(fresh)
        } catch {
            return "save failed " + describe(error)
        }
    }

    private func fetchById(_ id: String) -> String {
        do {
            let contact = try store.unifiedContact(withIdentifier: id, keysToFetch: keys)
            return "fetched \(contact.givenName) \(contact.familyName) " + Self.describe(contact)
        } catch {
            return "fetch \(id) failed " + describe(error)
        }
    }

    private func saveById(_ id: String) -> String {
        do {
            let contact = try store.unifiedContact(withIdentifier: id, keysToFetch: keys)
            let mutable = contact.mutableCopy() as! CNMutableContact
            mutable.emailAddresses.append(CNLabeledValue(label: CNLabelOther, value: "probe.added@example.org"))
            return save(mutable, id: id)
        } catch {
            return "fetch-for-save \(id) failed " + describe(error)
        }
    }

    private func presentPicker() -> String {
        let picker = CNContactPickerViewController()
        picker.delegate = self
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
        else { return "no root view controller" }
        root.present(picker, animated: true)
        return "picker presented"
    }

    private func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "error domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) info=\(ns.userInfo)"
    }

    static func describe(_ contact: CNContact) -> String {
        let emails = contact.emailAddresses.enumerated().map { index, value in
            "\(index + 1):\(CNLabeledValue<NSString>.localizedString(forLabel: value.label ?? "none"))=\(value.value)#\(value.identifier.prefix(8))"
        }
        return "emails[" + emails.joined(separator: ", ") + "]"
    }
}

extension Probe: CNContactPickerDelegate {
    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let id = contact.identifier
        let name = "\(contact.givenName) \(contact.familyName)"
        MainActor.assumeIsolated {
            log("picker returned \(name) id=\(id)")
            log("picker fetch: " + fetchById(id))
            log("picker save: " + saveById(id))
        }
    }

    nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        MainActor.assumeIsolated { log("picker cancelled") }
    }
}

private extension Array where Element == CNLabeledValue<NSString> {
    func reordered(toFront value: String) -> [CNLabeledValue<NSString>] {
        guard let index = firstIndex(where: { ($0.value as String) == value }) else { return self }
        var copy = self
        copy.insert(copy.remove(at: index), at: 0)
        return copy
    }

    func fresh() -> [CNLabeledValue<NSString>] {
        map { CNLabeledValue(label: $0.label, value: $0.value) }
    }

    func inserting(_ value: String, label: String) -> [CNLabeledValue<NSString>] {
        [CNLabeledValue(label: label, value: value as NSString)] + self
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withMillis: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
