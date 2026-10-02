import PrefillKit
import SwiftUI

// Values typed in Chrome or Arc that Prefill held back instead of saving, such as ones
// from a form the person left without sending.
struct ReviewList: View {
    @Environment(MacModel.self) private var model
    let items: [RecentItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Waiting for you").font(.headline)
            ForEach(items.prefix(Size.reviewRows)) { item in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
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
