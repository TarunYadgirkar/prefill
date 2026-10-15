import AuthenticationServices
import PrefillKit
import SwiftUI

// Prefill in iOS's AutoFill menu: long-press a text field in any app, choose AutoFill, then
// Prefill, and the value picked is inserted there. It declares only text insertion, never
// passwords or passkeys. It reads the same snapshot the app shares with the Prefill keyboard
// (its own App Group, nothing else), and has no network code.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    override func prepareInterfaceForUserChoosingTextToInsert() {
        let snapshot = (try? KeyboardShare.make().readSnapshot()) ?? nil
        let list = AutoFillList(
            values: snapshot?.values ?? [],
            pick: { [weak self] value in self?.insert(value) },
            cancel: { [weak self] in self?.cancel() }
        )
        let host = UIHostingController(rootView: list.tint(Palette.accent))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func insert(_ value: KeyboardValue) {
        extensionContext.completeRequest(withTextToInsert: value.text)
    }

    private func cancel() {
        extensionContext.cancelRequest(
            withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue)
        )
    }
}
