import Contacts
import ContactsUI
import SwiftUI

@main
struct ProbeApp: App {
    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

struct ProbeView: View {
    @State private var showAccessPicker = false
    @State private var last = ""
    private let probe = Probe.shared

    var body: some View {
        NavigationStack {
            List {
                Text(last).accessibilityIdentifier("last").font(.footnote)
                ForEach(Probe.Action.allCases, id: \.self) { action in
                    Button(action.rawValue) { run(action) }
                        .accessibilityIdentifier("action.\(action.rawValue)")
                }
                Button("accessPicker") { showAccessPicker = true }
                    .accessibilityIdentifier("action.accessPicker")
            }
            .navigationTitle("Contacts probe")
        }
        .contactAccessPicker(isPresented: $showAccessPicker) { ids in
            probe.log("contactAccessPicker returned \(ids)")
            last = "accessPicker \(ids.count)"
        }
        .task {
            probe.startWatching()
            if let name = UserDefaults.standard.string(forKey: "action"), let action = Probe.Action(rawValue: name) {
                run(action)
            }
        }
    }

    private func run(_ action: Probe.Action) {
        Task { last = await probe.run(action) }
    }
}
