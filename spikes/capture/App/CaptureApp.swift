import Contacts
import SwiftUI
import os

@main
struct CaptureApp: App {
    var body: some Scene {
        WindowGroup { CaptureList() }
    }
}

struct Capture: Identifiable {
    let id: Int
    let trigger: String
    let host: String
    let profile: String
    let fields: [(kind: String, value: String)]
    let latency: Double?
}

struct CaptureList: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var captures: [Capture] = []
    @State private var container = "?"
    @State private var contactsStatus = "?"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("App Group", value: container)
                        .accessibilityIdentifier("container")
                    LabeledContent("Contacts access", value: contactsStatus)
                    LabeledContent("Queued captures", value: "\(captures.count)")
                        .accessibilityIdentifier("captureCount")
                }
                ForEach(captures.reversed()) { capture in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(capture.host) via \(capture.trigger)").font(.headline)
                        ForEach(Array(capture.fields.enumerated()), id: \.offset) { _, field in
                            LabeledContent(field.kind, value: field.value)
                        }
                        if let latency = capture.latency {
                            Text("Written \(Int(latency)) ms after the event").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Captures")
            .refreshable { reload() }
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    }

    private func reload() {
        container = CaptureStore.containerURL?.path ?? "nil (no App Group entitlement)"
        contactsStatus = "\(CNContactStore.authorizationStatus(for: .contacts).rawValue)"
        captures = CaptureStore.readLines(CaptureStore.capturesFile).enumerated().map { index, line in
            let fields = (line["fields"] as? [[String: Any]] ?? []).map {
                (kind: $0["kind"] as? String ?? "?", value: $0["value"] as? String ?? "")
            }
            let start = line["t_handler_start"] as? Double
            let event = line["t_event"] as? Double
            return Capture(
                id: index,
                trigger: line["trigger"] as? String ?? "?",
                host: line["host"] as? String ?? "?",
                profile: line["profile"] as? String ?? "?",
                fields: fields,
                latency: start.flatMap { s in event.map { s - $0 } }
            )
        }
        Logger(subsystem: "com.tarunyadgirkar.prefill.spike.capture", category: "app")
            .log("app reload container=\(container, privacy: .public) captures=\(captures.count) contacts=\(contactsStatus, privacy: .public)")
    }
}
