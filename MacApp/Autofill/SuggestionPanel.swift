import AppKit
import PrefillKit
import SwiftUI

// What the panel shows: the rows that fit the field, which one the keyboard is on, and
// what picking one does.
@MainActor
@Observable
final class PanelModel {
    var rows: [AutofillRow] = []
    var selected: Int?
    // After "Fill form": what it did, shown in place of the rows with Undo.
    var notice: String?
    @ObservationIgnored var pick: (AutofillRow) -> Void = { _ in }
    @ObservationIgnored var fillForm: () -> Void = {}
    @ObservationIgnored var undoFill: () -> Void = {}

    func move(by step: Int) {
        guard !rows.isEmpty else { return }
        guard let selected else {
            self.selected = step > 0 ? 0 : rows.count - 1
            return
        }
        self.selected = (selected + step + rows.count) % rows.count
    }
}

// A borderless panel under the focused field, drawn like the Mac's own AutoFill list. It
// never becomes key and never activates Prefill, so the field keeps focus and the app in
// front stays in front.
@MainActor
final class SuggestionPanel {
    private static let minWidth: CGFloat = 240
    private static let maxWidth: CGFloat = 420

    let model = PanelModel()
    private let panel: NSPanel
    private let host: NSHostingView<PanelContent>

    init() {
        panel = FloatingPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let material = NSVisualEffectView()
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = PanelContent.cornerRadius
        material.layer?.masksToBounds = true
        host = FirstClickHostingView(rootView: PanelContent(model: model, rows: []))
        host.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            host.topAnchor.constraint(equalTo: material.topAnchor),
            host.bottomAnchor.constraint(equalTo: material.bottomAnchor)
        ])
        panel.contentView = material
    }

    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }

    // `field` is the field's frame from Accessibility (top-left based).
    func show(rows: [AutofillRow], under field: CGRect) {
        if rows != model.rows { model.selected = nil }
        model.rows = rows
        model.notice = nil
        place(under: field)
        panel.orderFrontRegardless()
    }

    func show(notice: String, under field: CGRect) {
        model.rows = []
        model.selected = nil
        model.notice = notice
        place(under: field)
        panel.orderFrontRegardless()
    }

    func place(under field: CGRect) {
        guard let primary = NSScreen.screens.first else { return }
        let appKitField = PanelGeometry.appKitRect(fromAX: field, primaryHeight: primary.frame.height)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: appKitField.midX, y: appKitField.midY)) }
            ?? primary
        let width = min(max(appKitField.width, Self.minWidth), Self.maxWidth)
        host.rootView = PanelContent(model: model, rows: model.rows, notice: model.notice, width: width)
        let size = CGSize(width: width, height: host.fittingSize.height)
        let frame = PanelGeometry.panelFrame(size: size, under: appKitField, visible: screen.visibleFrame)
        panel.setFrame(frame, display: true)
    }

    func hide() {
        panel.orderOut(nil)
        model.selected = nil
        model.notice = nil
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// The panel never becomes key, so the first click on a row has to count.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PanelContent: View {
    static let cornerRadius: CGFloat = 10
    static let inset: CGFloat = 5

    let model: PanelModel
    // Passed in rather than read from the model, so the panel's size follows them at once.
    let rows: [AutofillRow]
    var notice: String?
    var width: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice {
                HStack {
                    Label(notice, systemImage: "checkmark.circle")
                    Spacer(minLength: Spacing.xSmall)
                    Button("Undo") { model.undoFill() }
                        .buttonStyle(.link)
                }
                .padding(.horizontal, Spacing.xSmall)
                .padding(.vertical, 4)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    SuggestionRow(row: row, isSelected: model.selected == index)
                        .contentShape(.rect)
                        .onHover { if $0 { model.selected = index } }
                        .onTapGesture { model.pick(row) }
                }
            }
            Divider().padding(.vertical, Self.inset)
            HStack {
                Label("Prefill", systemImage: "person.text.rectangle")
                    .foregroundStyle(.secondary)
                Spacer(minLength: Spacing.xSmall)
                if notice == nil {
                    Button("Fill form") { model.fillForm() }
                        .buttonStyle(.link)
                        .help("Fills every empty field on this form that Prefill has a value for")
                }
            }
            .font(.caption)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.bottom, Spacing.hairline)
        }
        .padding(Self.inset)
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SuggestionRow: View {
    let row: AutofillRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            Image(systemName: Self.symbol(row.kind))
                .font(.body)
                .frame(width: 18)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.value)
                    .font(.body)
                    .foregroundStyle(valueStyle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(detailStyle)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, Spacing.xSmall)
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor : .clear,
            in: .rect(cornerRadius: PanelContent.cornerRadius - PanelContent.inset)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // A guess reads quieter than the person's own values, with its "Suggested" in the accent.
    private var valueStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.white) }
        return row.isGuess ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }

    private var detailStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.white.opacity(0.85)) }
        return row.isGuess ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "email": "envelope"
        case "phone": "phone"
        case "address": "house"
        case "name": "person"
        case "link": "link"
        default: "text.badge.checkmark"
        }
    }
}
