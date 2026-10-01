import Contacts
import Foundation
import SafariServices
import os

private let log = Logger(subsystem: "com.tarunyadgirkar.prefill.spike.capture", category: "handler")

private struct Unchecked<T>: @unchecked Sendable {
    let value: T
}

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let tStart = CaptureStore.nowMillis()
        let item = context.inputItems.first as? NSExtensionItem
        let profile = item?.userInfo?[SFExtensionProfileKey] as? UUID
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]

        var entry = message
        entry["profile"] = profile?.uuidString ?? "none"
        entry["t_handler_start"] = tStart
        entry["handler_pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        entry["contacts_status"] = statusName(CNContactStore.authorizationStatus(for: .contacts))
        entry["group_container"] = CaptureStore.containerURL?.path ?? "nil"

        var reply: [String: Any] = ["t_handler_start": tStart, "contacts_status": entry["contacts_status"] ?? "", "trigger": message["trigger"] ?? "", "t_event": message["t_event"] ?? 0, "t_bg": message["t_bg"] ?? 0, "url": message["url"] ?? "", "handler_pid": entry["handler_pid"] ?? 0]
        do {
            try CaptureStore.append(entry, to: CaptureStore.capturesFile)
            reply["t_written"] = CaptureStore.nowMillis()
        } catch {
            reply["write_error"] = describe(error)
        }
        let tEvent = message["t_event"] as? Double ?? 0
        reply["latency_event_to_written_ms"] = (reply["t_written"] as? Double ?? 0) - tEvent
        log.log("capture trigger=\(String(describing: message["trigger"]), privacy: .public) profile=\(profile?.uuidString ?? "none", privacy: .public) status=\(String(describing: entry["contacts_status"]), privacy: .public) container=\(CaptureStore.containerURL?.path ?? "nil", privacy: .public) reply=\(String(describing: reply), privacy: .public)")

        let url = message["url"] as? String ?? ""
        let box = Unchecked(value: (context, reply))
        guard url.contains("probe=1"), message["trigger"] as? String == "submit" else {
            finish(box.value.0, reply: box.value.1)
            return
        }
        Task {
            var r = box.value.1
            r["contacts_probe"] = await probeContacts()
            finish(box.value.0, reply: r)
        }
    }

}

private func finish(_ context: NSExtensionContext, reply: [String: Any]) {
        var line = reply
        line["t_reply"] = CaptureStore.nowMillis()
        try? CaptureStore.append(line, to: CaptureStore.handlerLogFile)
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: line]
        context.completeRequest(returningItems: [response], completionHandler: nil)
}

private func probeContacts() async -> [String: Any] {
        var r: [String: Any] = [:]
        let store = CNContactStore()
        let before = CNContactStore.authorizationStatus(for: .contacts)
        r["status_before"] = statusName(before)
        if before == .notDetermined {
            do {
                r["request_access_granted"] = try await store.requestAccess(for: .contacts)
            } catch {
                r["request_access_error"] = describe(error)
            }
            r["status_after_request"] = statusName(CNContactStore.authorizationStatus(for: .contacts))
        }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: "Alex Rivera")
        let contact: CNContact
        do {
            let found = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            r["fetch_count"] = found.count
            guard let first = found.first else { return r }
            contact = first
        } catch {
            r["fetch_error"] = describe(error)
            log.log("probe \(String(describing: r), privacy: .public)")
            return r
        }
        r["emails_before"] = emailList(contact)
        guard let mutable = contact.mutableCopy() as? CNMutableContact else { return r }
        var emails = mutable.emailAddresses
        if let last = emails.popLast() { emails.insert(last, at: 0) }
        mutable.emailAddresses = emails
        let request = CNSaveRequest()
        request.update(mutable)
        do {
            try store.execute(request)
            r["save"] = "ok"
            let refetched = try store.unifiedContact(withIdentifier: contact.identifier, keysToFetch: keys)
            r["emails_after"] = emailList(refetched)
        } catch {
            r["save_error"] = describe(error)
        }
        log.log("probe \(String(describing: r), privacy: .public)")
        return r
}

private func emailList(_ contact: CNContact) -> [String] {
    contact.emailAddresses.map { "\($0.label ?? "nil")=\($0.value as String)" }
}

private func statusName(_ status: CNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: "notDetermined(0)"
    case .restricted: "restricted(1)"
    case .denied: "denied(2)"
    case .authorized: "authorized(3)"
    case .limited: "limited(4)"
    @unknown default: "unknown(\(status.rawValue))"
    }
}

private func describe(_ error: Error) -> String {
    let e = error as NSError
    return "\(e.domain) code=\(e.code) \(e.localizedDescription) userInfo=\(e.userInfo)"
}
