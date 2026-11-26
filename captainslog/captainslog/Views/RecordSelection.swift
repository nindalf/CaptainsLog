import AppKit
import SwiftUI

/// The row `delta` rows from `current` among `ids`, clamped to the ends; with nothing selected,
/// the first row going down or the last going up.
func movedSelection<ID: Equatable>(_ current: ID?, by delta: Int, in ids: [ID]) -> ID? {
    guard !ids.isEmpty else { return nil }
    guard let current, let index = ids.firstIndex(of: current) else { return delta > 0 ? ids.first : ids.last }
    return ids[max(0, min(ids.count - 1, index + delta))]
}

/// Whether a text field or text view has the keyboard, so arrows and Return belong to it rather
/// than to the list around it. A text field edits through a text view too.
@MainActor
var isEditingText: Bool {
    NSApp.keyWindow?.firstResponder is NSTextView
}

/// Whether the click being handled is the second of a double-click. False for a tap that isn't a
/// mouse click, such as VoiceOver's press, whose event has no click count.
@MainActor
var isDoubleClick: Bool {
    guard let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp].contains(event.type) else { return false }
    return event.clickCount > 1
}

extension View {
    /// The one rule for a record in a list: a click selects it; a double-click, like Return, opens
    /// it. A record with notes opens as a page, a one-line record expands in place. Only a row
    /// already selected opens, so a card collapsing above it between the clicks can't move another
    /// row under the second.
    func onRecordClick(isSelected: Bool, select: @escaping () -> Void, open: @escaping () -> Void) -> some View {
        onTapGesture { if isDoubleClick && isSelected { open() } else { select() } }
    }

    /// The tint behind a selected row.
    func selectionHighlight(_ isSelected: Bool) -> some View {
        background(isSelected ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
    }
}
