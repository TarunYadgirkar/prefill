import SwiftUI

// What the keyboard's controls do, supplied by the input view controller.
struct KeyboardActions {
    var insert: (String) -> Void = { _ in }
    var nextKeyboard: () -> Void = {}
    var returnKey: () -> Void = {}
    var deleteBackward: () -> Void = {}
}

// The slim top row: ABC back to the person's own keyboard on the leading edge, return and
// delete on the trailing edge, where the system keyboard has them.
struct KeyboardBar: View {
    let returnLabel: String
    let actions: KeyboardActions

    var body: some View {
        HStack(spacing: KeyboardMetrics.gap) {
            Button(action: actions.nextKeyboard) {
                Text(verbatim: "ABC")
                    .font(.callout)
                    .foregroundStyle(KeyboardPalette.switchKey)
                    .frame(width: KeyboardMetrics.switchKeyWidth, height: KeyboardMetrics.keyHeight)
            }
            .buttonStyle(KeyboardKeyStyle())
            .accessibilityLabel(Text("Next keyboard"))
            .accessibilityHint(Text("Returns to your keyboard"))
            Spacer(minLength: 0)
            Button(action: actions.returnKey) {
                Text(returnLabel)
                    .font(.callout)
                    .foregroundStyle(KeyboardPalette.glyph)
                    .lineLimit(1)
                    .padding(.horizontal, KeyboardMetrics.rowPadding)
                    .frame(minWidth: KeyboardMetrics.returnKeyWidth, minHeight: KeyboardMetrics.keyHeight)
            }
            .buttonStyle(KeyboardKeyStyle())
            DeleteKey(deleteBackward: actions.deleteBackward)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(.horizontal, KeyboardMetrics.edge)
        .padding(.top, KeyboardMetrics.barTop)
    }
}

// A key surface with the system key's 1pt shadow, darker while held.
struct KeyboardKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .background(KeyboardKeyShape(isPressed: configuration.isPressed))
    }
}

struct KeyboardKeyShape: View {
    var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: KeyboardMetrics.radius, style: .continuous)
            .fill(isPressed ? KeyboardPalette.keyPressed : KeyboardPalette.key)
            .shadow(color: KeyboardPalette.keyShadow, radius: 0, x: 0, y: 1)
    }
}

// Deletes once on touch, then repeats while held, like the system delete key.
private struct DeleteKey: View {
    private static let firstRepeat = Duration.milliseconds(450)
    private static let repeatEvery = Duration.milliseconds(90)

    let deleteBackward: () -> Void
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        Image(systemName: repeater == nil ? "delete.left" : "delete.left.fill")
            .font(.title3)
            .foregroundStyle(KeyboardPalette.glyph)
            .frame(width: KeyboardMetrics.deleteKeyWidth, height: KeyboardMetrics.keyHeight)
            .background(KeyboardKeyShape(isPressed: repeater != nil))
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in start() }.onEnded { _ in stop() })
            .accessibilityElement()
            .accessibilityLabel(Text("Delete"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { deleteBackward() }
    }

    private func start() {
        guard repeater == nil else { return }
        deleteBackward()
        repeater = Task { @MainActor in
            try? await Task.sleep(for: Self.firstRepeat)
            while !Task.isCancelled {
                deleteBackward()
                try? await Task.sleep(for: Self.repeatEvery)
            }
        }
    }

    private func stop() {
        repeater?.cancel()
        repeater = nil
    }
}
