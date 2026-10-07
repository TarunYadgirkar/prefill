import PrefillKit
import SwiftUI

// Sites where the person chose "Don't save on this site" in Safari's Prefill sheet.
struct MutedSitesScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.state.mutedSites.isEmpty {
                EmptyStateView(
                    title: "No sites", systemImage: "nosign",
                    message: Text("""
                        To stop Prefill saving what you type on a site, open Prefill from Safari’s page menu there \
                        and turn on “Don’t save on this site”.
                        """)
                )
            } else {
                list
            }
        }
        .navigationTitle("Not saved on")
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.canvas)
    }

    private var list: some View {
        List {
            Section {
                ForEach(model.state.mutedSites.reversed(), id: \.self) { host in
                    HStack {
                        Text(host.breakableAtPunctuation)
                            .textRole(.body)
                        Spacer(minLength: Spacing.xSmall)
                        Button("Save here again") { model.saveAgain(on: host) }
                            .accessibilityLabel("Save on \(host) again")
                    }
                    .accessibilityIdentifier("muted-\(host)")
                }
            } footer: {
                Text("Prefill doesn’t save new emails, phone numbers, addresses or answers you type on these sites.")
                    .textRole(.footnote)
            }
        }
    }
}

#Preview {
    NavigationStack {
        MutedSitesScreen()
    }
    .previewModel()
}
