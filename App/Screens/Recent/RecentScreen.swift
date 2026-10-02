import PrefillKit
import SwiftUI

// Values the extension caught in Safari forms. Ones Prefill was sure about are already on
// the card and can come off again; the rest wait for Save or Don't save. Nothing leaves the
// list: a value taken off or not saved can still go on the card.
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
            .screenTitleDisplay()
            .background(Palette.canvas)
        }
    }
}

private struct RecentList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var waiting: [RecentItem] { items(.waiting) }
    private var saved: [RecentItem] { items(.saved) }
    private var removed: [RecentItem] { items(.removed) }

    var body: some View {
        List {
            if !waiting.isEmpty {
                Section {
                    ForEach(waiting) { item in
                        RecentRow(item: item)
                    }
                } header: {
                    Text("Waiting for you").textRole(.groupHeader)
                } footer: {
                    Text(model.state.settings.saveNewInfo
                        ? "Prefill wasn’t sure these are yours, so they aren’t on your card yet."
                        : "Save new info is off, so everything new waits here for you.")
                        .textRole(.footnote)
                }
            }
            if !saved.isEmpty {
                Section {
                    ForEach(saved) { item in
                        RecentRow(item: item)
                    }
                } header: {
                    Text("Saved to your card").textRole(.groupHeader)
                }
            }
            if !removed.isEmpty {
                Section {
                    ForEach(removed) { item in
                        RecentRow(item: item)
                    }
                } header: {
                    Text("Not on your card").textRole(.groupHeader)
                }
            }
        }
        .animation(Motion.state(reduceMotion: reduceMotion), value: model.recent)
    }

    private func items(_ state: RecentItem.State) -> [RecentItem] {
        model.recent.filter { $0.state == state }
    }
}

private struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let item: RecentItem
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                ValueRow(value: item.value, showsKindCaption: false)
                Text("Typed on \(item.host.breakableAtPunctuation) \(typedWhen)")
                    .textRole(.footnote)
            }
            actions
                .controlSize(.small)
                // A list row would set the icon in its own column, apart from the title and in the accent.
                .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, Spacing.xxSmall)
        // Without this the separator lines up with the action's title, past its icon.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .sensoryFeedback(.success, trigger: item.state) { _, new in new == .saved }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recent-\(item.value.display)")
    }

    private var typedWhen: String {
        item.date.formatted(.relative(presentation: .named))
    }

    @ViewBuilder private var actions: some View {
        switch item.state {
        case .waiting:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.small) { reviewButtons }
                VStack(alignment: .leading, spacing: Spacing.small) { reviewButtons }
            }
            .disabled(isWorking)
        case .saved:
            Button("Remove from card", systemImage: "minus.circle", role: .destructive) {
                run { await model.undo(item) }
            }
            .prefillButtonStyle(.rowDestructive)
            .disabled(isWorking)
        case .removed:
            Button("Save to card", systemImage: "arrow.uturn.backward") { run { await model.putBack(item) } }
                .prefillButtonStyle(.rowPrimary)
                .disabled(isWorking)
        }
    }

    @ViewBuilder private var reviewButtons: some View {
        Button("Save to card") { run { await model.save(item) } }
            .prefillButtonStyle(.rowPrimary)
        Button("Don’t save") { model.dismiss(item) }
            .prefillButtonStyle(.rowSecondary)
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
