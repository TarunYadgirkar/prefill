import AuthenticationServices
import SwiftUI
import os

let appLog = Logger(subsystem: "com.tarunyadgirkar.prefill.spike.textinsert", category: "app")

@main
struct SpikeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var status = "Not requested"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Turn on Prefill AutoFill") { Task { await requestTurnOn() } }
                        .accessibilityIdentifier("turnOn")
                    Text(status).accessibilityIdentifier("status")
                }
                Section {
                    Button("Open AutoFill provider settings") {
                        ASSettingsHelper.openCredentialProviderAppSettings { error in
                            appLog.notice("SPIKE openCredentialProviderAppSettings error=\(String(describing: error), privacy: .public)")
                        }
                    }
                    .accessibilityIdentifier("openSettings")
                    NavigationLink("Native text fields") { NativeFieldsScreen() }
                        .accessibilityIdentifier("nativeFields")
                }
            }
            .navigationTitle("Prefill Spike")
        }
    }

    private func requestTurnOn() async {
        status = "Requesting"
        let enabled = await ASSettingsHelper.requestToTurnOnCredentialProviderExtension()
        appLog.notice("SPIKE requestToTurnOnCredentialProviderExtension enabled=\(enabled, privacy: .public)")
        status = enabled ? "Enabled: true" : "Enabled: false"
    }
}

struct NativeFieldsScreen: View {
    @State private var emailEvents: [String] = []
    @State private var plainEvents: [String] = []

    var body: some View {
        Form {
            Section("UITextField, textContentType email") {
                LoggingField(placeholder: "Email", contentType: .emailAddress, keyboard: .emailAddress, events: $emailEvents)
                    .accessibilityIdentifier("nativeEmail")
                    .frame(height: 44)
                ForEach(Array(emailEvents.enumerated()), id: \.offset) { Text($0.element).font(.caption) }
            }
            Section("UITextField, no content type") {
                LoggingField(placeholder: "Anything", contentType: nil, keyboard: .default, events: $plainEvents)
                    .accessibilityIdentifier("nativePlain")
                    .frame(height: 44)
                ForEach(Array(plainEvents.enumerated()), id: \.offset) { Text($0.element).font(.caption) }
            }
        }
        .navigationTitle("Native fields")
    }
}

struct LoggingField: UIViewRepresentable {
    let placeholder: String
    let contentType: UITextContentType?
    let keyboard: UIKeyboardType
    @Binding var events: [String]

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.textContentType = contentType
        field.keyboardType = keyboard
        field.autocapitalizationType = .none
        field.borderStyle = .roundedRect
        field.accessibilityLabel = placeholder
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.addTarget(context.coordinator, action: #selector(Coordinator.began(_:)), for: .editingDidBegin)
        field.addTarget(context.coordinator, action: #selector(Coordinator.ended(_:)), for: .editingDidEnd)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(events: $events, name: placeholder) }

    @MainActor
    final class Coordinator: NSObject {
        let events: Binding<[String]>
        let name: String

        init(events: Binding<[String]>, name: String) {
            self.events = events
            self.name = name
        }

        @objc func began(_ field: UITextField) {
            appLog.notice("SPIKE native \(self.name, privacy: .public) editingDidBegin")
        }

        @objc func ended(_ field: UITextField) {
            appLog.notice("SPIKE native \(self.name, privacy: .public) editingDidEnd")
        }

        @objc func changed(_ field: UITextField) {
            let line = "editingChanged value=\(field.text ?? "")"
            appLog.notice("SPIKE native \(self.name, privacy: .public) \(line, privacy: .public)")
            events.wrappedValue = events.wrappedValue + [line]
        }
    }
}
