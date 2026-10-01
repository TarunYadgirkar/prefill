import SwiftUI

// One onboarding page: a title, an optional sentence under it, the page's own content, and
// its actions pinned above the home indicator so they never scroll away.
struct OnboardingStepLayout<Content: View, Actions: View>: View {
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text(title)
                        .textRole(.stepTitle)
                        .accessibilityAddTraits(.isHeader)
                    if let message {
                        Text(message)
                            .textRole(.body)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                content()
            }
            .frame(maxWidth: Size.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.large)
            .padding(.top, Spacing.xLarge)
            .padding(.bottom, Spacing.large)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: Spacing.small) {
                actions()
            }
            .frame(maxWidth: Size.readableWidth)
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.small)
        }
        .background(Palette.canvas)
    }
}
