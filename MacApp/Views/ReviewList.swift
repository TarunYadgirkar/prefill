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
            .foregroundStyle(isWaiting ? Palette.attention : Color.accentColor)
            .accessibilityHidden(true)
    }
}

private struct WaitingRow: View {
    @Environment(MacModel.self) private var model
    let item: RecentItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            InboxMark(isWaiting: true)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(item.value.display).lineLimit(2)
                Text("Typed on \(item.host)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add") { Task { await model.save(item) } }
                .accessibilityLabel("Add \(item.value.display) to your card")
            Button("Dismiss") { model.dismiss(item) }
                .accessibilityLabel("Dismiss \(item.value.display)")
        }
        .controlSize(.small)
    }
}

private struct LearnedRow: View {
    @Environment(MacModel.self) private var model
    let answer: LearnedAnswer

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            InboxMark(isWaiting: false)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(answer.value).lineLimit(2)
                Text("Learned from \(answer.host): \(answer.label)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove", role: .destructive) { Task { await model.removeLearned(answer) } }
                .accessibilityLabel("Remove \(answer.label) answer")
        }
        .controlSize(.small)
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
