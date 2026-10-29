// Dump every flavour currently on the general pasteboard: a summary table to stdout, and the
// full contents to one file per flavour. Useful for checking what "Copy for Slack" actually
// writes (public.html + public.utf8-plain-text) versus what plain Cmd-C writes (RTF).
//
// Run with `just pbdump`, or `swift scripts/pbdump.swift [outputDir]`.

import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/pbdump"
// Wipe first: a stale file from a previous run reads as a flavour that is still present.
try? FileManager.default.removeItem(atPath: outputDir)
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let pasteboard = NSPasteboard.general

// changeCount only advances on a genuine new copy, so this distinguishes "the app wrote nothing
// new" from "the dump did not re-run".
print("changeCount: \(pasteboard.changeCount)")

// Iterate items, not `pasteboard.types` — that reports the first item only, and a copy can
// place several items (one per selected message, say).
let items = pasteboard.pasteboardItems ?? []
guard !items.isEmpty else {
    print("Pasteboard is empty.")
    exit(0)
}

for (index, item) in items.enumerated() {
    let prefix = items.count > 1 ? "item \(index + 1): " : ""
    for type in item.types {
        guard let data = item.data(forType: type) else {
            print("\(prefix)\(type.rawValue)  unreadable")
            continue
        }
        // Non-UTF8 flavours (images, RTF with attachments) go out raw rather than mangled.
        let text = String(data: data, encoding: .utf8)
        let safeName = type.rawValue.replacingOccurrences(of: "/", with: "_")
        let name = items.count > 1 ? "\(index + 1)-\(safeName)" : safeName
        let path = "\(outputDir)/\(name).\(text == nil ? "bin" : "txt")"
        try? (text.map { Data($0.utf8) } ?? data).write(to: URL(fileURLWithPath: path))

        let label = (prefix + type.rawValue).padding(toLength: 40, withPad: " ", startingAt: 0)
        print("\(label)  \(data.count) bytes  ->  \(path)")
    }
}
