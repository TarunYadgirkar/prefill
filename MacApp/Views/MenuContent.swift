import PrefillKit
import SwiftUI

// The menu bar window: whether Prefill can work, then anything waiting for the person.
struct MenuContent: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            CardStatus()
            if !model.waiting.isEmpty {
                Divider()
                ReviewList(items: model.waiting)
            }
            Divider()
            BrowserList(browsers: model.browsers.filter(\.isInstalled))
            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit Prefill") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(Spacing.medium)
        .frame(width: Size.menuWidth)
    }
}

struct CardStatus: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        switch model.access {
        case .notDetermined:
            Notice(symbol: "person.crop.circle.badge.questionmark", title: "Prefill needs your contact card") {
                Button("Allow Contacts access") { Task { await model.requestAccess() } }
            }
        case .denied:
            Notice(symbol: "person.crop.circle.badge.xmark", title: "Contacts access is off") {
                Button("Open Privacy settings") { NSWorkspace.shared.open(Links.contactsPrivacy) }
            }
        case .granted:
            granted
        }
    }

    @ViewBuilder private var granted: some View {
        if model.hasMeCard, model.card != nil {
            Notice(symbol: "person.crop.circle.badge.checkmark", title: model.cardName, detail: summary) {
                EmptyView()
            }
        } else {
            Notice(
                symbol: "person.crop.circle.badge.exclamationmark", title: "Choose your own card",
                detail: "In Contacts, select your card and choose Card > Make This My Card."
            ) {
                EmptyView()
            }
        }
    }

    private var summary: String {
        let counts = [
            (model.values(.email).count, "email", "emails"),
            (model.values(.phone).count, "phone number", "phone numbers"),
            (model.values(.address).count, "address", "addresses")
        ]
        return counts.filter { $0.0 > 0 }.map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }.joined(separator: ", ")
    }
}

struct Notice<Actions: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions()
            }
        }
    }
}

enum Links {
    static let contactsPrivacy = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
    )!
}
