import AppKit
import Carbon.HIToolbox
import SwiftUI
import SwiftData
import CaptainsLogKit

/// Owns the Control-Space hotkey while `AppSettings.quickEntryEnabled` is on, and the panel it opens.
@MainActor
final class QuickEntryController {
    private let container: ModelContainer
    private let settings: AppSettings
    private var hotKey: GlobalHotKey?
    private var panel: QuickEntryPanel?

    init(container: ModelContainer, settings: AppSettings) {
        self.container = container
        self.settings = settings
        followSetting()
    }

    /// Registers or drops the hotkey to match the setting, then again on each change.
    private func followSetting() {
        let enabled = withObservationTracking {
            settings.quickEntryEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.followSetting() }
        }
        if enabled, hotKey == nil {
            hotKey = GlobalHotKey(keyCode: kVK_Space, modifiers: controlKey) { [weak self] in self?.show() }
        } else if !enabled, let hotKey {
            hotKey.unregister()
            self.hotKey = nil
            close()
        }
    }

    /// Opens a blank entry, or brings back the one already open.
    func show() {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = self.panel ?? QuickEntryPanel()
        self.panel = panel
        panel.onCancel = { [weak self] in self?.close() }
        let root = QuickEntryView(
            onClose: { [weak self] in self?.close() },
            onHeightChange: { [weak panel] height in
                // After the layout pass that measured it: resizing mid-layout throws.
                Task { @MainActor in panel?.fit(height: height) }
            }
        )
        .modelContainer(container)
        .environment(settings)
        let hosting = NSHostingView(rootView: root)
        // The panel sizes itself from the reported height, not through Auto Layout.
        hosting.sizingOptions = []
        panel.contentView = hosting
        // Placed from an estimate of the height now, then again once the view reports the real one.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen {
            let size = NSSize(width: QuickEntryView.width, height: hosting.fittingSize.height)
            panel.setFrame(QuickEntryPanel.centred(size, on: screen), display: false)
        }
        panel.centringScreen = screen
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        panel.orderOut(nil)
        // Dropping the view drops its draft, so the next open starts blank.
        panel.contentView = nil
    }
}

/// A floating panel that takes typing without activating the app, so the main window stays put
/// and closing hands focus back to whatever app was in front. Borderless and clear: the view
/// draws the rounded card and the system draws the shadow from its outline. A titled panel with
/// a hidden title bar looped resizing itself through the title bar's insets until AppKit threw.
final class QuickEntryPanel: NSPanel {
    var onCancel: () -> Void = {}
    /// The screen to centre on when the view first reports its height.
    var centringScreen: NSScreen?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }

    private static func firstEditableTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap(firstEditableTextField).first
    }

    /// Resizes to `height`. The first time after opening it centres the panel and puts the caret
    /// in the title; after that it keeps the top edge where it is, so notes grow downwards.
    func fit(height: CGFloat) {
        if let screen = centringScreen {
            centringScreen = nil
            setFrame(Self.centred(NSSize(width: QuickEntryView.width, height: height), on: screen), display: true)
            // SwiftUI's own focus request doesn't land when the panel opens over another app.
            // The view has rendered by its first height report, so its field exists.
            if let field = contentView.flatMap(Self.firstEditableTextField) { makeFirstResponder(field) }
        } else {
            guard abs(frame.height - height) > 0.5 else { return }
            var rect = frame
            rect.origin.y += rect.height - height
            rect.size.height = height
            setFrame(rect, display: true)
        }
        // The shadow follows the drawn outline, which has just changed.
        invalidateShadow()
    }

    /// Centred across the screen, its middle a third of the way down, where Things puts it.
    static func centred(_ size: NSSize, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - visible.height / 3 - size.height / 2
        )
        return NSRect(origin: origin, size: size)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}
