import Foundation
import os
import PrefillKit

// The Prefill keyboard can't reach Contacts, so the app hands it a copy of the values
// through the shared store whenever they may have changed.
extension AppModel {
    private static let keyboardLog = PrefillLog.logger("keyboard")

    func shareWithKeyboard() {
        guard let keyboard, let memory else { return }
        let snapshot = KeyboardSnapshot.make(memory: memory)
        guard snapshot.values != keyboardValues else { return }
        do {
            try keyboard.writeSnapshot(snapshot)
            keyboardValues = snapshot.values
        } catch {
            // The keyboard keeps the last copy; the next change tries again.
            Self.keyboardLog.error("keyboard values not shared")
        }
    }

    func readKeyboardSeen() {
        keyboardSeen = (try? keyboard?.readSeen()) ?? nil
    }
}
