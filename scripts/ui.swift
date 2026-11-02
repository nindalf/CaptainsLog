// Drives a sandboxed copy of the app for screenshots and UI checks. Run via `just ui <command>`.
// Coordinates are points relative to the main window's top-left corner.
// Input and `tree` need Accessibility permission for the terminal; `shot` needs Screen Recording.

import AppKit
import ApplicationServices
import ScreenCaptureKit

let usage = """
usage: ui <command>
  launch                launch the sandbox app (quits a previous sandbox instance)
  quit                  quit the sandbox app
  shot [name] [--retina]  capture the app's windows to .build/ui/shots/<name>.png (1x by default)
  tree [--all]          dump the accessibility tree of the main window
  click X Y [--cmd] [--shift] | dclick X Y | rclick X Y
  drag X1 Y1 X2 Y2      press at X1 Y1, move in steps to X2 Y2, release
  press <label> [--nth N]  click the centre of the Nth element whose label contains <label>
  key <combo>...        e.g. return, escape, down, cmd+n, cmd+shift+k
  type <text>           type text into the focused element
  move X Y              move the cursor to X Y (eased when UI_EASE_MS is set)
  frame W H [X Y]       resize the main window to W x H pt, optionally moving it to X Y on screen
  wait <ms>
For recordings: UI_EASE_MS=600 glides the cursor to each click instead of jumping, and
UI_TYPE_MS=70 types at a human pace.
"""

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let cwd = URL(filePath: FileManager.default.currentDirectoryPath)
let env = ProcessInfo.processInfo.environment
let appURL = URL(filePath: env["UI_APP"] ?? cwd.appending(path: ".build/xcode/Build/Products/Debug/Captain's Log.app").path(percentEncoded: false))
let storeDir = env["CAPTAINSLOG_STORE_DIR"] ?? cwd.appending(path: ".build/ui/store").path(percentEncoded: false)
let shotDir = cwd.appending(path: ".build/ui/shots")

// MARK: - Target app and windows

func sandboxApp() -> NSRunningApplication? {
    // UI_PID targets one process, e.g. a second instance of an app that's already running.
    if let pid = env["UI_PID"].flatMap(pid_t.init) { return NSRunningApplication(processIdentifier: pid) }
    return NSRunningApplication.runningApplications(withBundleIdentifier: Bundle(url: appURL)?.bundleIdentifier ?? "")
        .first { $0.bundleURL?.resolvingSymlinksInPath().path(percentEncoded: false).trimmingSuffix("/") == appURL.resolvingSymlinksInPath().path(percentEncoded: false).trimmingSuffix("/") }
}

func requireApp() throws -> NSRunningApplication {
    guard let app = sandboxApp() else { throw Failure("sandbox app not running; run `just ui launch`") }
    return app
}

struct Window {
    let id: Int
    let layer: Int
    let bounds: CGRect
}

func windows(pid: pid_t) -> [Window] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
              let id = w[kCGWindowNumber as String] as? Int,
              let layer = w[kCGWindowLayer as String] as? Int,
              let dict = w[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict),
              layer != Int(CGWindowLevelForKey(.statusWindow)),
              bounds.width > 1, bounds.height > 1
        else { return nil }
        return Window(id: id, layer: layer, bounds: bounds)
    }
}

func mainWindow(pid: pid_t) throws -> Window {
    guard let w = windows(pid: pid).filter({ $0.layer == 0 }).max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
    else { throw Failure("no on-screen window for the sandbox app") }
    return w
}

// MARK: - Accessibility

func requireTrust() throws {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else {
        throw Failure("Accessibility permission missing: System Settings > Privacy & Security > Accessibility, enable your terminal app, then restart it")
    }
}

func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func frame(_ el: AXUIElement) -> CGRect? {
    guard let pos: AXValue = attr(el, kAXPositionAttribute), let size: AXValue = attr(el, kAXSizeAttribute) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pos, .cgPoint, &p)
    AXValueGetValue(size, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

func label(_ el: AXUIElement) -> String {
    var parts: [String] = []
    for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute, kAXHelpAttribute] {
        if let s: String = attr(el, name), !s.isEmpty {
            let short = s.count > 80 ? String(s.prefix(80)) + "..." : s
            parts.append("\(name.replacingOccurrences(of: "AX", with: "").lowercased())=\(short.debugDescription)")
        }
    }
    return parts.joined(separator: " ")
}

func axMainWindow(_ app: NSRunningApplication) throws -> AXUIElement {
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    if let w: AXUIElement = attr(appEl, kAXMainWindowAttribute) { return w }
    if let ws: [AXUIElement] = attr(appEl, kAXWindowsAttribute), let w = ws.first { return w }
    throw Failure("no accessibility window for the sandbox app")
}

func walk(_ el: AXUIElement, depth: Int = 0, visit: (AXUIElement, Int) -> Void) {
    visit(el, depth)
    for child in (attr(el, kAXChildrenAttribute) as [AXUIElement]?) ?? [] {
        walk(child, depth: depth + 1, visit: visit)
    }
}

/// Popovers and sheets are separate AX windows; include them alongside the main window.
func axRoots(_ app: NSRunningApplication) throws -> [AXUIElement] {
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    let all: [AXUIElement] = attr(appEl, kAXWindowsAttribute) ?? []
    return all.isEmpty ? [try axMainWindow(app)] : all
}

// MARK: - Input

func activate(_ app: NSRunningApplication) {
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    if let w = try? axMainWindow(app) { AXUIElementPerformAction(w, kAXRaiseAction as CFString) }
    usleep(150_000)
}

func toGlobal(_ app: NSRunningApplication, _ x: Double, _ y: Double) throws -> CGPoint {
    let origin = try mainWindow(pid: app.processIdentifier).bounds.origin
    return CGPoint(x: origin.x + x, y: origin.y + y)
}

let easeMS = Int(env["UI_EASE_MS"] ?? "") ?? 0
let typeMS = Int(env["UI_TYPE_MS"] ?? "") ?? 15

/// Glides from the current cursor position with ease-in-out, so recordings don't show the cursor jump.
func glide(to point: CGPoint) {
    let from = CGEvent(source: nil)?.location ?? point
    let distance = hypot(point.x - from.x, point.y - from.y)
    guard easeMS > 0, distance > 2 else {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        return
    }
    // Short hops take less time than long ones, but never under a third of the full duration.
    let ms = Double(easeMS) * max(0.35, min(1, distance / 700))
    let steps = max(10, Int(ms / 8))
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        let p = CGPoint(x: from.x + (point.x - from.x) * e, y: from.y + (point.y - from.y) * e)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(useconds_t(ms * 1000 / Double(steps)))
    }
    usleep(120_000)
}

func mouse(_ point: CGPoint, button: CGMouseButton, clicks: Int, flags: CGEventFlags = []) {
    let (down, up): (CGEventType, CGEventType) = button == .right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
    glide(to: point)
    usleep(50_000)
    for n in 1...clicks {
        for type in [down, up] {
            let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
            e?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
        usleep(60_000)
    }
}

let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
    "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
    ".": 47, "`": 50,
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
    "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "left": 123, "right": 124, "down": 125, "up": 126,
]

func key(_ combo: String) throws {
    var parts = combo.lowercased().split(separator: "+").map(String.init)
    guard let name = parts.popLast(), let code = keyCodes[name] else { throw Failure("unknown key in \(combo)") }
    var flags = CGEventFlags()
    for m in parts {
        switch m {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt", "alt", "option": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        default: throw Failure("unknown modifier \(m)")
        }
    }
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        usleep(20_000)
    }
}

func type(_ text: String) {
    for ch in text {
        let units = Array(String(ch).utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            e?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            e?.post(tap: .cghidEventTap)
        }
        // A little jitter reads as typing rather than a machine.
        let base = Double(typeMS)
        usleep(useconds_t(1000 * (typeMS > 15 ? base * Double.random(in: 0.6...1.5) : base)))
    }
}

func frameCommand(_ args: [String]) throws {
    try requireTrust()
    let n = args.compactMap(Double.init)
    guard n.count == 2 || n.count == 4 else { throw Failure("expected W H [X Y]") }
    let app = try requireApp()
    let w = try axMainWindow(app)
    if n.count == 4 {
        var p = CGPoint(x: n[2], y: n[3])
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v) }
    }
    var s = CGSize(width: n[0], height: n[1])
    if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v) }
    usleep(200_000)
    let b = try mainWindow(pid: app.processIdentifier).bounds
    print("window \(Int(b.width))x\(Int(b.height)) pt at \(Int(b.minX)),\(Int(b.minY))")
}

// MARK: - Commands

func quit() async {
    guard let app = sandboxApp() else { return }
    app.terminate()
    for _ in 0..<50 where !app.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
    if !app.isTerminated { app.forceTerminate() }
}

func launch() async throws {
    guard FileManager.default.fileExists(atPath: appURL.path(percentEncoded: false)) else { throw Failure("no app at \(appURL.path(percentEncoded: false)); run `just ui-build`") }
    await quit()
    try FileManager.default.createDirectory(atPath: storeDir, withIntermediateDirectories: true)
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.environment = env.merging(["CAPTAINSLOG_STORE_DIR": storeDir]) { $1 }
    // Keep the sandbox from restoring (or overwriting) the real app's saved window state.
    config.arguments = ["-ApplePersistenceIgnoreState", "YES"]
    let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    for _ in 0..<100 {
        if let w = try? mainWindow(pid: app.processIdentifier) {
            print("launched pid \(app.processIdentifier), window \(Int(w.bounds.width))x\(Int(w.bounds.height)) pt, store \(storeDir)")
            return
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    throw Failure("app launched but no window appeared")
}

func shot(_ args: [String]) async throws {
    let app = try requireApp()
    let retina = args.contains("--retina")
    let name = args.first { !$0.hasPrefix("--") } ?? ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "")
    // ScreenCaptureKit composites only this app's windows (popovers and menus included), so overlapping apps never leak in.
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    let ours = content.windows.filter {
        $0.owningApplication?.processID == app.processIdentifier
            && $0.windowLayer != Int(CGWindowLevelForKey(.statusWindow))
            && $0.frame.width > 1 && $0.frame.height > 1
    }
    guard let main = ours.filter({ $0.windowLayer == 0 }).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    else { throw Failure("no on-screen window for the sandbox app") }
    let rect = ours.map(\.frame).reduce(main.frame) { $0.union($1) }
    guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: main.frame.midX, y: main.frame.midY)) }) ?? content.displays.first
    else { throw Failure("no display") }
    let filter = SCContentFilter(display: display, including: ours)
    let scale = retina ? CGFloat(filter.pointPixelScale) : 1
    let config = SCStreamConfiguration()
    config.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    config.width = Int(rect.width * scale)
    config.height = Int(rect.height * scale)
    config.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw Failure("PNG encoding failed") }
    try FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
    let url = shotDir.appending(path: "\(name).png")
    try png.write(to: url)
    var line = "\(url.path(percentEncoded: false)) (\(Int(rect.width))x\(Int(rect.height)) pt, \(retina ? "2x" : "1x"))"
    let offset = CGPoint(x: main.frame.minX - rect.minX, y: main.frame.minY - rect.minY)
    if offset != .zero { line += ", main window at +\(Int(offset.x)),+\(Int(offset.y)) in image" }
    print(line)
}

func tree(_ args: [String]) throws {
    try requireTrust()
    let app = try requireApp()
    let origin = try mainWindow(pid: app.processIdentifier).bounds.origin
    let all = args.contains("--all")
    for root in try axRoots(app) {
        walk(root) { el, depth in
            let role: String = attr(el, kAXRoleAttribute) ?? "?"
            let text = label(el)
            guard all || !text.isEmpty || depth == 0 || ["AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRow", "AXCell"].contains(role) else { return }
            var line = String(repeating: "  ", count: depth) + role
            if let sub: String = attr(el, kAXSubroleAttribute) { line += "/\(sub)" }
            if let f = frame(el) { line += " [\(Int(f.minX - origin.x)),\(Int(f.minY - origin.y)) \(Int(f.width))x\(Int(f.height))]" }
            if (attr(el, kAXFocusedAttribute) as Bool?) == true { line += " FOCUSED" }
            if !text.isEmpty { line += " " + text }
            print(line)
        }
    }
}

func press(_ args: [String]) throws {
    try requireTrust()
    let app = try requireApp()
    var words = args
    var nth = 1
    if let i = words.firstIndex(of: "--nth"), i + 1 < words.count {
        nth = Int(words[i + 1]) ?? 1
        words.removeSubrange(i...(i + 1))
    }
    let needle = words.joined(separator: " ").lowercased()
    var matches: [CGRect] = []
    for root in try axRoots(app) {
        walk(root) { el, _ in
            if label(el).lowercased().contains(needle), let f = frame(el), f.width > 0 { matches.append(f) }
        }
    }
    guard matches.count >= nth else { throw Failure("\(matches.count) element(s) match \(needle.debugDescription)") }
    let f = matches[nth - 1]
    activate(app)
    mouse(CGPoint(x: f.midX, y: f.midY), button: .left, clicks: 1)
    let origin = try mainWindow(pid: app.processIdentifier).bounds.origin
    print("clicked \(Int(f.midX - origin.x)),\(Int(f.midY - origin.y)) (match \(nth) of \(matches.count))")
}

/// Moves in small steps so gesture recognisers see a drag, not a jump.
func dragCommand(_ args: [String]) throws {
    try requireTrust()
    let n = args.compactMap(Double.init)
    guard n.count == 4 else { throw Failure("expected X1 Y1 X2 Y2") }
    let app = try requireApp()
    activate(app)
    let from = try toGlobal(app, n[0], n[1]), to = try toGlobal(app, n[2], n[3])
    func post(_ type: CGEventType, _ point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    post(.mouseMoved, from)
    usleep(50_000)
    post(.leftMouseDown, from)
    usleep(80_000)
    let steps = 20
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        usleep(25_000)
    }
    usleep(150_000)
    post(.leftMouseUp, to)
}

func clickCommand(_ args: [String], button: CGMouseButton, clicks: Int) throws {
    try requireTrust()
    let coords = args.filter { !$0.hasPrefix("--") }
    guard coords.count == 2, let x = Double(coords[0]), let y = Double(coords[1]) else { throw Failure("expected X Y") }
    // Real modifier key presses, not just event flags: apps read NSEvent.modifierFlags at click time.
    var held: [(key: CGKeyCode, flag: CGEventFlags)] = []
    if args.contains("--cmd") { held.append((0x37, .maskCommand)) }
    if args.contains("--shift") { held.append((0x38, .maskShift)) }
    let flags = CGEventFlags(held.map(\.flag))
    let app = try requireApp()
    activate(app)
    for (key, _) in held { modifierKey(key, down: true, flags: flags) }
    mouse(try toGlobal(app, x, y), button: button, clicks: clicks, flags: flags)
    for (key, _) in held.reversed() { modifierKey(key, down: false, flags: []) }
}

func modifierKey(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
    e?.flags = flags
    e?.post(tap: .cghidEventTap)
    usleep(30_000)
}

let argv = Array(CommandLine.arguments.dropFirst())
do {
    guard let command = argv.first else { throw Failure(usage) }
    let rest = Array(argv.dropFirst())
    switch command {
    case "launch": try await launch()
    case "quit": await quit()
    case "shot": try await shot(rest)
    case "tree": try tree(rest)
    case "click": try clickCommand(rest, button: .left, clicks: 1)
    case "dclick": try clickCommand(rest, button: .left, clicks: 2)
    case "rclick": try clickCommand(rest, button: .right, clicks: 1)
    case "drag": try dragCommand(rest)
    case "press": try press(rest)
    case "key":
        try requireTrust()
        activate(try requireApp())
        for combo in rest { try key(combo); usleep(80_000) }
    case "type":
        try requireTrust()
        activate(try requireApp())
        type(rest.joined(separator: " "))
    case "move":
        let n = rest.compactMap(Double.init)
        guard n.count == 2 else { throw Failure("expected X Y") }
        glide(to: try toGlobal(try requireApp(), n[0], n[1]))
    case "frame": try frameCommand(rest)
    case "wait": try await Task.sleep(for: .milliseconds(Int(rest.first ?? "") ?? 500))
    default: throw Failure(usage)
    }
} catch {
    FileHandle.standardError.write(Data("ui: \(error)\n".utf8))
    exit(1)
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String { hasSuffix(suffix) ? String(dropLast(suffix.count)) : self }
}
