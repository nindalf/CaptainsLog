import AppKit
import SwiftData
import SwiftUI
import CaptainsLogKit

/// Lets the SwiftUI wrapper's key handlers and buttons reach the live controller. A reference
/// type, so an `onKeyPress` closure kept from an earlier render still sees the current one.
final class MarkdownEditorHandle {
    weak var controller: MarkdownEditorController?
}

/// The native markdown field: an `NSTextView` that restyles only what each edit touches.
struct NativeMarkdownField: NSViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var minHeight: CGFloat = 20
    var maxHeight: CGFloat?
    /// Whether the caller's `FocusState` points here; nil when the caller does not track focus.
    var isFocused: Bool?
    var onFocusChange: ((Bool) -> Void)?
    var onReturn: (() -> Void)?
    var handle: MarkdownEditorHandle?

    func makeCoordinator() -> MarkdownEditorController {
        MarkdownEditorController()
    }

    func makeNSView(context: Context) -> MarkdownScrollView {
        let controller = context.coordinator
        handle?.controller = controller
        controller.configure(self, modelContext: context.environment.modelContext)
        controller.load(text)
        return controller.scrollView
    }

    func updateNSView(_ scrollView: MarkdownScrollView, context: Context) {
        handle?.controller = context.coordinator
        context.coordinator.update(self, modelContext: context.environment.modelContext)
    }

    static func dismantleNSView(_ scrollView: MarkdownScrollView, coordinator: MarkdownEditorController) {
        coordinator.tearDown()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarkdownScrollView, context: Context) -> CGSize? {
        var width = proposal.width ?? nsView.frame.width
        if !width.isFinite || width <= 0 { width = nsView.frame.width > 0 ? nsView.frame.width : 300 }
        return CGSize(width: width, height: context.coordinator.fittingHeight(width: width))
    }
}

final class MarkdownScrollView: NSScrollView {
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }

    /// Short notes sit inside scrolling detail views; a field with nothing to scroll passes the
    /// wheel on rather than swallowing it.
    override func scrollWheel(with event: NSEvent) {
        let canScroll = (documentView?.frame.height ?? 0) > contentView.bounds.height + 1
        if canScroll {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
}

final class MarkdownEditorController: NSObject, NSTextViewDelegate {
    let textView = MarkdownTextView.make()
    let scrollView = MarkdownScrollView()
    let highlighter = MarkdownHighlighter()
    private let completer = TagCompleter()
    private let undo = UndoManager()

    private var text: Binding<String> = .constant("")
    private var onReturn: (() -> Void)?
    private var onFocusChange: ((Bool) -> Void)?
    private var minHeight: CGFloat = 20
    private var maxHeight: CGFloat?

    /// The text last written to or read from the binding.
    private var lastSynced = ""
    /// Typing not yet written to the binding.
    private var isDirty = false
    private var flushTask: Task<Void, Never>?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var reportedHeight: CGFloat = 0
    private var lastFocusRequest: Bool?
    private var pendingFocus: Bool?

    override init() {
        super.init()
        textView.controller = self
        completer.textView = textView
        textView.delegate = self
        textView.textStorage?.delegate = highlighter
        textView.layoutManager?.delegate = highlighter

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView
        scrollView.onWindowChange = { [weak self] in self?.windowDidChange() }

        let center = NotificationCenter.default
        for name in [NSApplication.willTerminateNotification, NSApplication.willResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            })
        }
    }

    // MARK: SwiftUI bridge

    func configure(_ field: NativeMarkdownField, modelContext: ModelContext) {
        text = field.$text
        onReturn = field.onReturn
        onFocusChange = field.onFocusChange
        minHeight = field.minHeight
        maxHeight = field.maxHeight
        completer.modelContext = modelContext
        if textView.placeholder != field.placeholder { textView.placeholder = field.placeholder }
        if let request = field.isFocused, request != lastFocusRequest {
            lastFocusRequest = request
            requestFocus(request)
        }
    }

    func update(_ field: NativeMarkdownField, modelContext: ModelContext) {
        let previous = text
        let heights = (minHeight, maxHeight)
        configure(field, modelContext: modelContext)
        if heights != (minHeight, maxHeight) { updateHeight(force: true) }

        // Nothing is written to the binding here: a value written during a SwiftUI update reads
        // back stale for the rest of it, and a write to `@State` then can be dropped altogether.
        let value = field.text
        guard value != lastSynced else { return }
        // The text changed from outside: this editor now shows another note, or the note was
        // edited elsewhere. Typing not yet written belongs to the note it was typed into.
        if isDirty {
            cancelPendingFlush()
            isDirty = false
            write(textView.string, to: previous, deferred: true)
        }
        lastSynced = value
        if value != textView.string { replaceText(with: value) }
    }

    func load(_ value: String) {
        lastSynced = value
        replaceText(with: value)
    }

    func tearDown() {
        flush(deferred: true)
        completer.end()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    /// Swap in text from outside the editor. Not undoable: the undo stack describes the old text.
    private func replaceText(with value: String) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: value)
        let length = storage.length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        undo.removeAllActions()
        updateHeight(force: true)
    }

    // MARK: Writing the binding

    /// Write pending typing to the binding. `deferred` for callers that may be inside a SwiftUI
    /// update, such as losing focus or being torn down.
    func flush(deferred: Bool = false) {
        cancelPendingFlush()
        guard isDirty else { return }
        isDirty = false
        let value = textView.string
        lastSynced = value
        write(value, to: text, deferred: deferred)
    }

    private func write(_ value: String, to binding: Binding<String>, deferred: Bool) {
        if deferred {
            DispatchQueue.main.async { binding.wrappedValue = value }
        } else {
            binding.wrappedValue = value
        }
    }

    private func cancelPendingFlush() {
        flushTask?.cancel()
        flushTask = nil
        removeEventMonitor()
    }

    /// Writing the model on every keystroke re-renders whatever observes it and wakes every
    /// `@Query` on the next save, so typing is written in bursts instead.
    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
        installEventMonitor()
    }

    /// While typing is unwritten, write it before anything else can act on the model: a click
    /// anywhere, or a key that could reach a button or list handler.
    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            if event.type != .keyDown || Self.mayActOutsideEditor(event) { self?.flush() }
            return event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    private static func mayActOutsideEditor(_ event: NSEvent) -> Bool {
        if !event.modifierFlags.intersection([.command, .control]).isEmpty { return true }
        // Return, Enter, Escape, Tab.
        return [36, 76, 53, 48].contains(event.keyCode)
    }

    // MARK: Height

    private var isFixedHeight: Bool {
        maxHeight.map { $0 <= minHeight } ?? false
    }

    func fittingHeight(width: CGFloat) -> CGFloat {
        if isFixedHeight { return minHeight }
        let natural = contentHeight(width: width)
        return min(max(natural, minHeight), maxHeight ?? .greatestFiniteMagnitude)
    }

    private func contentHeight(width: CGFloat) -> CGFloat {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return minHeight }
        let containerWidth = max(width, 1)
        if abs(container.size.width - containerWidth) > 0.5 {
            container.size = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        // Past the cap the field scrolls, so there is no need to lay out the rest to size it.
        if let maxHeight {
            layoutManager.ensureLayout(forBoundingRect: NSRect(x: 0, y: 0, width: containerWidth, height: maxHeight + 1), in: container)
        } else {
            layoutManager.ensureLayout(for: container)
        }
        return ceil(layoutManager.usedRect(for: container).height)
    }

    private func updateHeight(force: Bool = false) {
        guard !isFixedHeight else { return }
        let width = scrollView.contentSize.width
        guard width > 0 else { return }
        let height = fittingHeight(width: width)
        if force || abs(height - reportedHeight) > 0.5 {
            reportedHeight = height
            scrollView.invalidateIntrinsicContentSize()
        }
    }

    // MARK: Focus

    private func requestFocus(_ focused: Bool) {
        pendingFocus = focused
        // After this update, when the field is in its window.
        DispatchQueue.main.async { [weak self] in self?.applyPendingFocus() }
    }

    private func windowDidChange() {
        if textView.window == nil {
            flush(deferred: true)
            completer.end()
        } else {
            applyPendingFocus()
        }
    }

    private func applyPendingFocus() {
        guard let focused = pendingFocus, let window = textView.window else { return }
        pendingFocus = nil
        if focused, window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        } else if !focused, window.firstResponder === textView {
            window.makeFirstResponder(nil)
        }
    }

    func focusDidChange(_ focused: Bool) {
        if !focused {
            flush(deferred: true)
            completer.end()
        }
        // Not on resigning: the binding can still read focused for a render after SwiftUI moves
        // focus away, and that would look like a new request and pull focus back.
        if focused { lastFocusRequest = true }
        onFocusChange?(focused)
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        isDirty = true
        scheduleFlush()
        updateHeight()
        completer.update()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        completer.update()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        undo
    }

    func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            if let onReturn, !shift {
                flush()
                onReturn()
                return true
            }
            guard textView.continueBlockOnNewline() else { return false }
            // `replace` moves the caret without scrolling, so scroll as a plain newline does.
            textView.scrollRangeToVisible(textView.selectedRange())
            return true
        case #selector(NSResponder.insertTab(_:)):
            return textView.indentLines(outdent: false)
        case #selector(NSResponder.insertBacktab(_:)):
            return textView.indentLines(outdent: true)
        case #selector(NSResponder.cancelOperation(_:)):
            // Not NSTextView's own word-completion popup, which is what Escape opens by default.
            return true
        default:
            return false
        }
    }

    /// Return as SwiftUI sees it, before the text view does.
    func handleReturnKey(modifiers: EventModifiers) -> KeyPress.Result {
        if let onReturn, modifiers.isDisjoint(with: [.shift, .command]) {
            flush()
            onReturn()
            return .handled
        }
        return .ignored
    }
}
