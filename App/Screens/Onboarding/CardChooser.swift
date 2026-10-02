import PrefillKit
import SwiftUI

struct CardChooser: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [OnboardingRoute]
    @State private var cards: [CardChoice] = []
    @State private var query = ""
    @State private var linking: CardChoice.ID?

    private var shown: [CardChoice] {
        guard !query.isEmpty else { return cards }
        return cards.filter {
            $0.name.localizedStandardContains(query) || ($0.detail ?? "").localizedStandardContains(query)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(shown) { card in
                    row(card)
                }
            } footer: {
                Text("""
                    Pick the card that Safari lists as My Info. That card holds the emails, phone numbers and \
                    addresses Safari suggests.
                    """)
                    .textRole(.footnote)
            }
        }
        .navigationTitle("Which card is yours?")
        .screenTitleDisplay()
        .searchable(text: $query, prompt: "Name or email")
        .overlay {
            if !cards.isEmpty && shown.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task { cards = await model.contacts.cards() }
    }

    private func row(_ card: CardChoice) -> some View {
        Button {
            Task { await choose(card) }
        } label: {
            HStack(spacing: Spacing.small) {
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(card.name).textRole(.value)
                    if let detail = card.detail {
                        Text(detail.breakableAtPunctuation).textRole(.valueCaption)
                    }
                }
                Spacer(minLength: 0)
                if linking == card.id {
                    ProgressView()
                } else if card.id == model.state.cardLink?.contactIdentifier {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.accent)
                        .accessibilityLabel("Your card now")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Uses this card as yours")
        .disabled(linking != nil)
    }

    private func choose(_ card: CardChoice) async {
        linking = card.id
        await model.link(card)
        linking = nil
        if model.state.cardLink?.contactIdentifier == card.id {
            path.removeAll()
        }
    }
}

#Preview {
    NavigationStack {
        CardChooser(path: .constant([.chooser]))
    }
    .previewModel(.preview(linked: false, finished: false))
}
