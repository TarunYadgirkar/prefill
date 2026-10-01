import PrefillKit
import SwiftUI

struct SitesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
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
                    SiteList(path: $path)
                }
            }
            .navigationTitle("Sites")
            .navigationDestination(for: String.self) { host in
                SiteDetail(host: host)
            }
            .background(Palette.canvas)
        }
    }
}

private struct SiteList: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [String]

    var body: some View {
        List {
            if !model.state.settings.matchEachSite {
                Section {
                    MatchOffNote()
                }
            }
            ForEach(model.sites) { site in
                // A plain button rather than a NavigationLink, so the bar keeps the row's full
                // width instead of giving some of it to the disclosure chevron.
                Section {
                    Button {
                        path.append(site.host)
                    } label: {
                        SiteRow(site: site)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(
                        top: Spacing.small, leading: Spacing.small, bottom: Spacing.small, trailing: Spacing.small
                    ))
                    .accessibilityHint("Shows what Safari offers on this site")
                    .accessibilityIdentifier("site-\(site.host)")
                }
            }
        }
        .listSectionSpacing(Spacing.medium)
    }
}

private struct SiteRow: View {
    let site: SiteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(spacing: Spacing.xSmall) {
                Text(site.host)
                    .textRole(.bodyEmphasis)
                if site.pinned[.email] != nil {
                    Image(systemName: "pin.fill")
                        .textRole(.rowIcon)
                        .accessibilityLabel("Email pinned")
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .textRole(.rowIcon)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.xSmall)
            QuickTypeBar(kind: .email, values: site.values(.email), style: .compact)
        }
        .padding(.vertical, Spacing.xxSmall)
    }
}

struct MatchOffNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Match each site is off, so every site gets your card's own order.")
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
