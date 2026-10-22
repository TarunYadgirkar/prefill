import Foundation
import PrefillKit
import SafariServices

// Safari on the Mac runs Prefill's extension here, in a sandbox without Contacts. Each message
// goes to the running Prefill app over the socket in the shared group container, and the app
// answers with the same MessageRouter as for Chrome.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let message = (context.inputItems.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey]
        DispatchQueue.global(qos: .userInitiated).async {
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: Self.answer(message)]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    private static func answer(_ message: Any?) -> Any {
        guard let message, JSONSerialization.isValidJSONObject(message),
              let body = try? JSONSerialization.data(withJSONObject: message),
              let request = try? MessageCoding.validatedRequest(body, allowingSheet: true)
        else { return MessageCoding.jsonObject(.error(reason: "unknown message")) }
        let app = RelayClient.enclosingApp(of: Bundle.main.bundleURL)
        guard let path = RelaySocket.safariPath,
              let reply = RelayClient.send(request, to: path, launching: app),
              let object = try? JSONSerialization.jsonObject(with: reply)
        else { return MessageCoding.jsonObject(.error(reason: "Prefill isn't running on this Mac. Open Prefill.")) }
        return object
    }
}
