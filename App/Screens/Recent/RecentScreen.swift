import PrefillKit
import SwiftUI

// Values the extension caught in Safari forms. Ones Prefill was sure about are already on
// the card and can be undone; the rest wait for Save or Dismiss.
struct RecentScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.recent.isEmpty {
                    EmptyStateView(
                        title: "Nothing new yet", systemImage: "tray",
                        message: Text("""
                            When you type a new email, phone number or address into a form in Safari, it shows \
                            up here.
                            """)
                    )
                } else {
                    RecentList()
                }
            }
            .navigationTitle("Recently added")
            .background(Palette.canvas)
        }
    }
}

private struct RecentList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var waiting: [RecentItem] { model.recent.filter { $0.state == .waiting } }
    private var saved: [RecentItem] { model.recent.filter { $0.state != .waiting } }

    var body: some View {
        List {
            if !waiting.isEmpty {
                Section {
                    ForEach(waiting) { item in
                        RecentRow(item: item)
                    }
                } header: {
                    Text("Waiting for you")
                } footer: {
                    Text(model.state.settings.saveNewInfo
                        ? "Prefill wasn't sure these are yours, so they aren't on your card yet."
                        : "Save new info is off, so everything new waits here for you.")
                        .textRole(.footnote)
                }
            }
            if !saved.isEmpty {
                Section("Saved to your card") {
                    ForEach(saved) { item in
                        RecentRow(item: item)
                    }
                }
            }
        }
        .animation(Motion.state(reduceMotion: reduceMotion), value: model.recent)
    }
}

private struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let item: RecentItem
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ValueRow(value: item.value) {
                if item.state == .removed {
                    Text("Removed")
                        .textRole(.secondary)
                }
            }
            .opacity(item.state == .removed ? 0.5 : 1)
            Text("On \(item.host) \(item.date.formatted(.relative(presentation: .named)))")
                .textRole(.footnote)
            actions
        }
        .padding(.vertical, Spacing.xxSmall)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recent-\(item.value.display)")
    }

    @ViewBuilder private var actions: some View {
        switch item.state {
        case .waiting:
            HStack(spacing: Spacing.small) {
                Button("Save to card") { run { await model.save(item) } }
                    .fontWeight(.semibold)
                Button("Dismiss") { model.dismiss(item) }
                    .tint(Palette.textSecondary)
            }
            .buttonStyle(.glass)
            .disabled(isWorking)
        case .saved:
            Button("Undo", systemImage: "arrow.uturn.backward") { run { await model.undo(item) } }
                .buttonStyle(.glass)
                .disabled(isWorking)
                .accessibilityLabel("Undo, take it off your card")
        case .removed:
            EmptyView()
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }
}

#Preview {
    RecentScreen()
        .previewModel()
}
