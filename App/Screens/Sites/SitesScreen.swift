import PrefillKit
import SwiftUI

// Pushed from Settings, whose stack opens each site (SiteDetail) by its host.
struct SitesScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.sites.isEmpty {
                EmptyStateView(
                    title: "No sites yet", systemImage: "globe",
                    message: Text("""
                        After you fill in a form in Safari, the site shows up here with the values Safari \
                        suggests there.
                        """)
                )
            } else {
                SiteList()
            }
        }
        .navigationTitle("Sites")
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.canvas)
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
                    .accessibilityHint("Shows what Safari suggests on this site")
                    .accessibilityIdentifier("site-\(site.host)")
                }
            }
        }
    }
}

// The site and the email Safari suggests there first, written out in full so the list scans
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
                Spacer(minLength: Spacing.xSmall)
                if let kind = site.kind.title {
                    SiteKindTag(title: kind)
                }
            }
            if let first = site.values(.email).first {
                Text("Suggests \(first.payload.barText.breakableAtPunctuation) first")
                    .textRole(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.xxSmall)
    }
}

// What kind of site this is, which decides the value Safari offers on a first visit.
private struct SiteKindTag: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .textRole(.footnote)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.hairline)
            .background(Palette.highlight, in: .capsule)
            .accessibilityLabel(Text("\(Text(title)) site"))
    }
}

struct MatchOffNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Putting the value you used on a site first is off, so every site gets your own order.")
                .textRole(.body)
            Button("Turn it on") {
                model.setMatchEachSite(true)
            }
        }
        .padding(.vertical, Spacing.xxSmall)
    }
}

#Preview {
    NavigationStack {
        SitesScreen()
            .navigationDestination(for: String.self) { SiteDetail(host: $0) }
    }
    .previewModel()
}
