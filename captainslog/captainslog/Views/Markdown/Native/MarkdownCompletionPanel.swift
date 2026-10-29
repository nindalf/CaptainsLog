import AppKit
import SwiftUI

// The `@` / `#` suggestion list, floating under the caret in a borderless child window so no
// list row or card can clip it. It never becomes key: the text view keeps the keyboard, and the
// editor drives the highlight from its arrow-key handling.

struct MarkdownCompletionRow: Identifiable {
    let id: UUID
    var leading: String?
    var title: String
    var detail: String?
    var trailing: String?
}

@Observable
final class MarkdownCompletionModel {
    var rows: [MarkdownCompletionRow] = []
    var selected = 0
    var onPick: (Int) -> Void = { _ in }
}

final class MarkdownCompletionPanel {
    static let shared = MarkdownCompletionPanel()

    static let rowHeight: CGFloat = 24
    private static let width: CGFloat = 380
    private static let padding: CGFloat = 5

    private let model = MarkdownCompletionModel()
    private let panel: NSPanel
    /// The editor the list is showing for, so one editor closing it cannot hide another's.
    private(set) weak var owner: AnyObject?

    private init() {
        panel = CompletionWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        let host = FirstMouseHostingView(rootView: MarkdownCompletionList(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.topAnchor.constraint(equalTo: background.topAnchor),
            host.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
    }

    /// Show `rows` under `caret`, a rect in screen coordinates, attached to `parent`.
    func show(
        rows: [MarkdownCompletionRow],
        selected: Int,
        caret: NSRect,
        parent: NSWindow,
        owner: AnyObject,
        onPick: @escaping (Int) -> Void
    ) {
        self.owner = owner
        model.rows = rows
        model.selected = selected
        model.onPick = onPick

        let height = CGFloat(rows.count) * Self.rowHeight + Self.padding * 2
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        var origin = NSPoint(x: caret.minX - 10, y: caret.minY - height - 4)
        if origin.y < screen.minY { origin.y = caret.maxY + 4 }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - Self.width - 4)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: Self.width, height: height)), display: true)

        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func select(_ index: Int) {
        model.selected = index
    }

    func hide(owner: AnyObject) {
        guard self.owner === owner else { return }
        self.owner = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}

private final class CompletionWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A click on a row should act at once, not first activate the panel.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct MarkdownCompletionList: View {
    let model: MarkdownCompletionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                let isSelected = index == model.selected
                HStack(spacing: 6) {
                    if let leading = row.leading {
                        Text(leading)
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    }
                    Text(row.title)
                        .lineLimit(1)
                    if let detail = row.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    }
                    Spacer(minLength: 8)
                    if let trailing = row.trailing {
                        Text(trailing)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.tertiary))
                    }
                }
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 8)
                .frame(height: MarkdownCompletionPanel.rowHeight)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5).fill(Color.accentColor)
                    }
                }
                .contentShape(.rect)
                .onTapGesture { model.onPick(index) }
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
