import Foundation
import PrefillKit
import SafariServices
import os

private let log = PrefillLog.logger("extension")

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let router = MessageRouter(store: StoreFactory.make(), gateway: CNContactStoreGateway())
        let reply = router.route(item?.userInfo?[SFExtensionMessageKey])
        log.debug("replied \(reply.typeName, privacy: .public)")
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: MessageCoding.jsonObject(reply)]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
