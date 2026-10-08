import PrefillKit
import SwiftUI

// The state of an inbox row, in shape and color so it never rests on color alone: a ring
// waits for the person, a check is on the card, a minus came off it, circling arrows mark an
// answer a form changed and a sparkle the on-device model's guess.
struct InboxMark: View {
    enum Kind {
        case waiting, saved, removed, changed, guess
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
        case .changed: "arrow.triangle.2.circlepath"
        case .guess: "sparkle"
        }
    }

    private var color: Color {
        switch kind {
        case .waiting: Palette.attention
        case .saved: Palette.positive
        case .removed: Palette.pending
        case .changed, .guess: Palette.accent
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

// An answer a form changed. Keep takes it off the inbox; Change back puts the old one back.
struct ChangedRow: View {
    @Environment(AppModel.self) private var model
    let answer: LearnedAnswer
    let field: CustomField
    let edit: () -> Void

    var body: some View {
        InboxRowFrame(mark: .changed, line: line) {
            AnswerText(field: field)
        } actions: {
            // Side by side while they fit; stacked at the largest text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.small) { buttons }
                VStack(alignment: .leading, spacing: Spacing.small) { buttons }
            }
        }
        .accessibilityIdentifier("changed-\(answer.label)")
    }

    private var line: Text {
        let site = answer.host.breakableAtPunctuation
        return Text("Changed on \(site) from “\(answer.previous ?? "")”")
    }

    @ViewBuilder private var buttons: some View {
        Button("Keep") { model.markSeen(answer) }
            .prefillButtonStyle(.rowPrimary)
            .accessibilityIdentifier("inbox-keep")
        Button("Change back") { Task { await model.changeBack(answer, field: field) } }
            .prefillButtonStyle(.rowSecondary)
            .accessibilityIdentifier("inbox-change-back")
        Button("Edit", systemImage: "pencil", action: edit)
            .prefillButtonStyle(.rowSecondary)
            .accessibilityIdentifier("inbox-edit")
    }
}

// The on-device model's pick of a saved answer for a question no rule matched. Until the
// person says Use it, the answer is only offered under the field, never filled.
struct GuessRow: View {
    @Environment(AppModel.self) private var model
    let guess: GuessToConfirm

    var body: some View {
        InboxRowFrame(mark: .guess, line: line) {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(verbatim: guess.question.text).textRole(.valueCaption)
                Text(guess.field.value).textRole(.value).fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.small) { buttons }
                VStack(alignment: .leading, spacing: Spacing.small) { buttons }
            }
        }
        .accessibilityIdentifier("guess-\(guess.field.label)")
    }

    private var line: Text {
        let site = guess.question.host.breakableAtPunctuation
        return Text("Apple Intelligence suggests your \(guess.field.label) answer here, asked on \(site)")
    }

    @ViewBuilder private var buttons: some View {
        Button("Use it") { model.confirm(guess) }
            .prefillButtonStyle(.rowPrimary)
            .accessibilityIdentifier("inbox-use-guess")
        Button("Not this") { model.reject(guess) }
            .prefillButtonStyle(.rowSecondary)
            .accessibilityIdentifier("inbox-reject-guess")
    }
}
