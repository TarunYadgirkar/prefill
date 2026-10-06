import PrefillKit
import SwiftUI

// The state of an inbox row, in shape and color so it never rests on color alone: a ring
// waits for the person, a check is on the card, a minus came off it, a pin is first on a
// site and a sparkle was learned from an application.
struct InboxMark: View {
    enum Kind {
        case waiting, saved, removed, picked, learned
    }

    let kind: Kind
    @ScaledMetric(relativeTo: .body) private var width = Size.statusMark

    var body: some View {
        Image(systemName: symbol)
            .font(TextRole.rowIcon.font)
            .foregroundStyle(color)
            .frame(width: width)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch kind {
        case .waiting: "circle"
        case .saved: "checkmark.circle.fill"
        case .removed: "minus.circle"
        case .picked: "pin.fill"
        case .learned: "sparkle"
        }
    }

    private var color: Color {
        switch kind {
        case .waiting: Palette.attention
        case .saved: Palette.positive
        case .removed: Palette.pending
        case .picked, .learned: Palette.accent
        }
    }
}

// Every inbox row: the mark, what Prefill holds, one line on what happened, then the
// actions that fit.
struct InboxRowFrame<Content: View, Actions: View>: View {
    let mark: InboxMark.Kind
    let line: Text
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            InboxMark(kind: mark)
            VStack(alignment: .leading, spacing: Spacing.small) {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    content()
                    line.textRole(.footnote)
                }
                actions()
                    .controlSize(.small)
                    // A list row would set the icon in its own column, apart from the title.
                    .labelStyle(.titleAndIcon)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.xxSmall)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .accessibilityElement(children: .contain)
    }
}

extension InboxRowFrame where Actions == EmptyView {
    init(mark: InboxMark.Kind, line: Text, @ViewBuilder content: @escaping () -> Content) {
        self.init(mark: mark, line: line, content: content) { EmptyView() }
    }
}

// An answer Prefill saved from a job application. Edit opens the same editor as the You tab.
struct LearnedRow: View {
    @Environment(AppModel.self) private var model
    let answer: LearnedAnswer
    let edit: () -> Void

    var body: some View {
        InboxRowFrame(
            mark: .learned, line: Text("Learned from \(answer.host.breakableAtPunctuation): \(answer.label)")
        ) {
            Text(answer.value)
                .textRole(.value)
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            // Side by side while they fit; stacked at the largest text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.small) { buttons }
                VStack(alignment: .leading, spacing: Spacing.small) { buttons }
            }
        }
        .accessibilityIdentifier("answer-\(answer.label)")
    }

    @ViewBuilder private var buttons: some View {
        Button("Edit", systemImage: "pencil", action: edit)
            .prefillButtonStyle(.rowSecondary)
            .accessibilityIdentifier("inbox-edit")
        Button("Remove", systemImage: "minus.circle", role: .destructive) {
            Task { await model.undo(answer) }
        }
        .prefillButtonStyle(.rowDestructive)
        .accessibilityIdentifier("inbox-remove-answer")
    }
}

// A value the person picked on a site, which Prefill now offers first there.
struct PickedRow: View {
    let pick: FirstPick

    var body: some View {
        InboxRowFrame(mark: .picked, line: Text("""
            Picked on \(pick.site.breakableAtPunctuation) \(pick.date.formatted(.relative(presentation: .named))), \
            so it’s first there
            """)) {
            ValueRow(value: pick.value)
        }
        .accessibilityIdentifier("picked-\(pick.value.display)")
    }
}
