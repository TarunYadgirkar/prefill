import PrefillKit
import SwiftUI

struct SitesScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.sites.isEmpty {
                    EmptyStateView(
                        title: "No sites yet", systemImage: "globe",
                        message: Text("""
                            After you fill in a form in Safari, the site shows up here with the values Prefill \
                            offers there.
                            """)
                    )
                } else {
                    SiteList()
                }
            }
            .navigationTitle("Sites")
            .screenTitleDisplay()
            .navigationDestination(for: String.self) { host in
                SiteDetail(host: host)
            }
            .background(Palette.canvas)
        }
    }
}

private struct SiteList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if !model.state.settings.matchEachSite {
                Section {
                    MatchOffNote()
                }
            }
            Section {
                ForEach(model.sites) { site in
                    NavigationLink(value: site.host) {
                        SiteRow(site: site)
                    }
                    .accessibilityHint("Shows what Safari offers on this site")
                    .accessibilityIdentifier("site-\(site.host)")
                }
            }
        }
    }
}

// The site and the email Safari offers there first, written out in full so the list scans
// by host and by value. The site screen shows the bar itself.
private struct SiteRow: View {
    let site: SiteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            HStack(spacing: Spacing.xSmall) {
                Text(site.host.breakableAtPunctuation)
                    .textRole(.bodyEmphasis)
                if site.pinned[.email] != nil {
                    Image(systemName: "pin.fill")
                        .textRole(.rowIcon)
                        .accessibilityLabel("Email pinned")
                }
            }
            if let first = site.values(.email).first {
                Text("Offers \(first.payload.barText.breakableAtPunctuation) first")
                    .textRole(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.xxSmall)
    }
}

struct MatchOffNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Match each site is off, so every site gets your card’s own order.")
                .textRole(.body)
            Button("Turn on Match each site") {
                model.setMatchEachSite(true)
            }
        }
        .padding(.vertical, Spacing.xxSmall)
    }
}

#Preview {
    SitesScreen()
        .previewModel()
}
