import PrefillKit
import SwiftUI
import UIKit

// The Prefill keyboard. It reads the values the app shares through the keychain group (or
// the App Group), types the one the person taps and hands them back to their own keyboard.
// It has no network code and writes only when it was last shown (to the shared store) and
// its own recent picks (to its own defaults).
final class KeyboardViewController: UIInputViewController {
    private let share = KeyboardShare.make()
    private var host: UIHostingController<KeyboardPanel>?
    private var snapshot: KeyboardSnapshot?
    private let picks = KeyboardPicks()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: panel())
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.height)
        height.priority = .defaultHigh + 1
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height
        ])
        host.didMove(toParent: self)
        self.host = host
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        snapshot = hasFullAccess ? (try? share.readSnapshot()) ?? nil : nil
        if hasFullAccess { try? share.writeSeen(.now) }
        refresh()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        refresh()
    }

    private func refresh() {
        host?.rootView = panel()
    }

    private func panel() -> KeyboardPanel {
        KeyboardPanel(content: content, returnLabel: FieldTraits.returnLabel(textDocumentProxy.returnKeyType),
                      actions: actions)
    }

    private var content: KeyboardPanel.Content {
        if FieldTraits.isSensitive(textDocumentProxy) { return .notHere }
        guard hasFullAccess else { return .needsFullAccess }
        guard let snapshot, !snapshot.values.isEmpty else { return .needsApp }
        return .values(snapshot.ranked(for: context))
    }

    private var context: KeyboardContext {
        KeyboardContext(
            before: textDocumentProxy.documentContextBeforeInput ?? "",
            hint: FieldTraits.hint(textDocumentProxy),
            recentPicks: picks.recents.ids
        )
    }

    private var actions: KeyboardActions {
        KeyboardActions(
            insert: { [weak self] value in self?.insert(value) },
            nextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            returnKey: { [weak self] in self?.textDocumentProxy.insertText("\n") },
            deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() }
        )
    }

    private func insert(_ value: KeyboardValue) {
        let replaced = context.replacedLength(for: value)
        for _ in 0..<replaced { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(value.text)
        picks.record(value.id)
        advanceToNextInputMode()
    }
}
