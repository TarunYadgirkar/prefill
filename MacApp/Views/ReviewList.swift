import PrefillKit
import SwiftUI

// The menu's inbox: values typed in a browser that Prefill held back instead of saving, such
// as ones from a form the person left without sending, answers from applications sent lately
// to save or not, then answers it learned from job applications before.
struct ReviewList: View {
    @Environment(MacModel.self) private var model

    private var learned: [LearnedAnswer] { Array(model.learnedAnswers.prefix(Size.learnedRows)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            if model.waiting.isEmpty && learned.isEmpty && model.answerOffers.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text("Nothing new").font(.headline)
                    Text("Answers from applications you send show up here for you to save.")
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
            if !model.answerOffers.isEmpty {
                Text("Save these answers?").font(.headline)
                ForEach(model.answerOffers) { offer in
                    OfferRow(offer: offer)
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

// An answer from an application the person sent. It is saved only when they say Save.
private struct OfferRow: View {
    @Environment(MacModel.self) private var model
    let offer: AnswerOffer

    var body: some View {
        let detail = "\(offer.field.label), answered on \(offer.host)"
        return ReviewRow(isWaiting: true, value: offer.field.value, detail: detail) {
            Button("Save") { Task { await model.save(offer) } }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Save \(offer.field.label) answer")
            Button("Don’t save") { model.dismiss(offer) }
                .accessibilityLabel("Don’t save \(offer.field.label) answer")
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

// Each installed Chromium browser and whether Prefill's extension has talked from it. Without
// the extension the Accessibility panel still fills text fields there, but nothing is saved,
// learned or recorded, so the list says so.
struct BrowserList: View {
    let browsers: [BrowserHost]
    let heard: Set<String>

    private var lacksExtension: Bool {
        browsers.contains { $0.hasHost && !heard.contains($0.bundleID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("Browsers").font(.headline)
            if browsers.isEmpty {
                Text("Prefill works in Safari. Chrome, Arc, Brave and Edge show here once installed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(browsers) { browser in
                BrowserRow(browser: browser, hasExtension: heard.contains(browser.bundleID))
            }
            if lacksExtension {
                Text("""
                    Without Prefill’s extension, a browser gets at most suggestions for text fields. Prefill \
                    saves no new answers there and records no applications.
                    """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Add the extension") { ChromeExtensionHelp() }
                    .font(.callout)
            }
        }
    }
}

private struct BrowserRow: View {
    let browser: BrowserHost
    let hasExtension: Bool

    private var status: LocalizedStringKey {
        if !browser.hasHost { return "Couldn’t connect" }
        return hasExtension ? "Extension on" : "No extension yet"
    }

    private var symbol: String {
        if !browser.hasHost { return "exclamationmark.triangle.fill" }
        return hasExtension ? "checkmark.circle.fill" : "circle.dashed"
    }

    private var tint: Color {
        if !browser.hasHost { return Palette.warning }
        return hasExtension ? Palette.positive : .secondary
    }

    var body: some View {
        LabeledContent {
            Text(status).font(.callout).foregroundStyle(.secondary)
        } label: {
            Label {
                Text(browser.name)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
        }
    }
}
