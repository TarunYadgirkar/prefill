import AuthenticationServices
import SwiftUI
import os

private let log = Logger(subsystem: "com.tarunyadgirkar.prefill.spike.textinsert", category: "provider")

private let spikeValues = ["ti-one@example.net", "ti-two@example.net", "+1 415 555 0103"]

final class CredentialProviderViewController: ASCredentialProviderViewController {
    override func prepareInterfaceForUserChoosingTextToInsert() {
        log.notice("SPIKE prepareInterfaceForUserChoosingTextToInsert")
        show(title: "Prefill values")
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        log.notice("SPIKE prepareCredentialList ids=\(serviceIdentifiers.map(\.identifier), privacy: .public)")
        show(title: "Prefill passwords (none)")
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        log.notice("SPIKE prepareInterfaceToProvideCredential")
        show(title: "Prefill credential")
    }

    private func show(title: String) {
        if Bundle.main.object(forInfoDictionaryKey: "SpikeUIKitList") as? Bool == true {
            return showUIKit()
        }
        let list = ValueList(
            title: title,
            values: spikeValues,
            pick: { [weak self] value in self?.insert(value) },
            cancel: { [weak self] in self?.cancel() }
        )
        let host = UIHostingController(rootView: list)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func showUIKit() {
        log.notice("SPIKE using UIKit list")
        view.backgroundColor = .systemBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for value in spikeValues {
            let b = UIButton(type: .system, primaryAction: UIAction(title: value) { [weak self] _ in self?.insert(value) })
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(UIButton(type: .system, primaryAction: UIAction(title: "Cancel") { [weak self] _ in self?.cancel() }))
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
        ])
    }

    private func insert(_ value: String) {
        log.notice("SPIKE completeRequest(withTextToInsert:) value=\(value, privacy: .public)")
        extensionContext.completeRequest(withTextToInsert: value) { expired in
            log.notice("SPIKE completeRequest completion expired=\(expired, privacy: .public)")
        }
    }

    private func cancel() {
        log.notice("SPIKE cancelRequest")
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue))
    }
}

private struct ValueList: View {
    let title: String
    let values: [String]
    let pick: (String) -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            List(values, id: \.self) { value in
                Button(value) { pick(value) }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
            }
        }
    }
}
