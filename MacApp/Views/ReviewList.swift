import PrefillKit
import SwiftUI

// The menu's inbox: values typed in Chrome or Arc that Prefill held back instead of saving,
// such as ones from a form the person left without sending, then answers it learned from
// job applications lately.
struct ReviewList: View {
    @Environment(MacModel.self) private var model

    private var learned: [LearnedAnswer] { Array(model.learnedAnswers.prefix(Size.learnedRows)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            if model.waiting.isEmpty && learned.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text("Nothing new").font(.headline)
                    Text("Prefill adds what you type into forms, and it shows up here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !model.waiting.isEmpty {
                Text("Needs you").font(.headline)
                ForEach(model.waiting.prefix(Size.reviewRows)) { item in
                    WaitingRow(item: item)
                }
            }
            if !learned.isEmpty {
                Text("Learned").font(.headline)
                ForEach(learned) { answer in
                    LearnedRow(answer: answer)
                }
            }
        }
    }
}

// A state mark in shape and color, as on the iPhone: a ring waits, a sparkle was learned.
private struct InboxMark: View {
    let isWaiting: Bool

    var body: some View {
        Image(systemName: isWaiting ? "circle" : "sparkle")
            .foregroundStyle(isWaiting ? Palette.attention : Palette.accent)
            .accessibilityHidden(true)
    }
}

// Each row: the mark, the value with where it came from, then its actions under it, so a
// long email keeps the menu's width instead of being cut off beside the buttons.
private struct ReviewRow<Actions: View>: View {
    let isWaiting: Bool
    let value: String
    let detail: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            InboxMark(isWaiting: isWaiting)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(value).lineLimit(2).truncationMode(.middle)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: Spacing.xSmall) { actions() }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WaitingRow: View {
    @Environment(MacModel.self) private var model
    let item: RecentItem

    var body: some View {
        ReviewRow(isWaiting: true, value: item.value.display, detail: "Typed on \(item.host)") {
            Button("Add to card") { Task { await model.save(item) } }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add \(item.value.display) to your card")
            Button("Dismiss") { model.dismiss(item) }
                .accessibilityLabel("Dismiss \(item.value.display)")
        }
    }
}

private struct LearnedRow: View {
    @Environment(MacModel.self) private var model
    let answer: LearnedAnswer

    var body: some View {
        ReviewRow(isWaiting: false, value: answer.value, detail: "\(answer.label), learned from \(answer.host)") {
            Button("Remove", role: .destructive) { Task { await model.removeLearned(answer) } }
                .accessibilityLabel("Remove \(answer.label) answer")
        }
    }
}

struct BrowserList: View {
    let browsers: [BrowserHost]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("Browsers").font(.headline)
            if browsers.isEmpty {
                Text("Install Chrome or Arc to use Prefill on this Mac.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(browsers) { browser in
                Label {
                    Text(browser.name)
                } icon: {
                    Image(systemName: browser.hasHost ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(browser.hasHost ? Palette.positive : Palette.warning)
                }
                .accessibilityValue(browser.hasHost ? "Connected" : "Couldn’t connect")
            }
        }
    }
}
