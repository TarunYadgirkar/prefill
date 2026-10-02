import AppIntents

struct PrefillShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetValueIntent(kind: .email),
            phrases: [
                "Which email do I use on \(\.$site) in \(.applicationName)",
                "What's my email for \(\.$site) in \(.applicationName)",
                "What's my email in \(.applicationName)"
            ],
            shortTitle: "Email for a site",
            systemImageName: "envelope"
        )
        AppShortcut(
            intent: GetValueIntent(kind: .address, purpose: .shipping),
            phrases: [
                "What's my shipping address in \(.applicationName)",
                "Get my shipping address from \(.applicationName)"
            ],
            shortTitle: "Shipping address",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: GetValueIntent(),
            phrases: [
                "What's my \(\.$kind) in \(.applicationName)",
                "Which \(\.$kind) does \(.applicationName) suggest"
            ],
            shortTitle: "Contact info",
            systemImageName: "person.text.rectangle"
        )
    }
}
