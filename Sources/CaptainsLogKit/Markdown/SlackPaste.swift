import Foundation

// Slack -> markdown, the paste direction.
//
// Slack's `public.utf8-plain-text` flavour is lossy: emphasis markers are stripped and link URLs
// are dropped entirely, so there is nothing to recover from it. The formatting lives in the
// `org.chromium.web-custom-data` flavour (Slack is an Electron app), which holds a map with two
// useful entries: `slack/texty` (a Quill delta) and `text/markdown` (markdown, ready to use).

/// MIME key holding Slack's own markdown rendering of the copied message.
public let slackMarkdownMIMEType = "text/markdown"

/// Decode Chromium's `org.chromium.web-custom-data` pasteboard flavour into its MIME-type map.
///
/// The payload is a Chromium `Pickle`: `uint32` payload size, `uint32` entry count, then repeated
/// `uint32` character count + UTF-16LE characters, with every field realigned to 4 bytes.
/// Pasteboard data is untrusted, so every read is bounds-checked and a malformed payload decodes
/// to whatever prefix was valid rather than trapping.
public func decodeWebCustomData(_ data: Data) -> [String: String] {
    let bytes = [UInt8](data)
    var cursor = 0

    func readUInt32() -> Int? {
        guard cursor + 4 <= bytes.count else { return nil }
        let value = UInt32(bytes[cursor])
            | UInt32(bytes[cursor + 1]) << 8
            | UInt32(bytes[cursor + 2]) << 16
            | UInt32(bytes[cursor + 3]) << 24
        cursor += 4
        return Int(value)
    }

    func readString16() -> String? {
        // The count guard also bounds `count * 2`, so the offsets below cannot overflow.
        guard let count = readUInt32(), count <= (bytes.count - cursor) / 2 else { return nil }
        var units = [UInt16]()
        units.reserveCapacity(count)
        for i in 0..<count {
            let offset = cursor + i * 2
            units.append(UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
        }
        cursor += count * 2
        cursor += (4 - cursor % 4) % 4
        return String(decoding: units, as: UTF16.self)
    }

    // Entry count is capped: a real payload carries a handful of flavours, and a garbage read
    // here would otherwise drive a very long loop.
    guard readUInt32() != nil, let entryCount = readUInt32(), entryCount <= 64 else { return [:] }

    var entries: [String: String] = [:]
    for _ in 0..<entryCount {
        guard let key = readString16(), let value = readString16() else { break }
        entries[key] = value
    }
    return entries
}

/// Repair the one place Slack's markdown is not valid CommonMark: a formatted run ending in a
/// space is emitted as `**text **`, but CommonMark will not close an emphasis run on whitespace,
/// so the run renders literally and the formatting is lost. Move the space outside the closing
/// delimiter.
///
/// Only the two-character delimiters are repaired. A single `~` or `*` is indistinguishable from
/// ordinary prose — `approx ~5 and ~10` has the exact shape of a strikethrough run ending in a
/// space, and "fixing" it would corrupt the text into `~5 and~ 10`. Two-character runs carry no
/// such ambiguity. The cost is that an italic run ending in a space (Slack emits `*italic *`)
/// keeps losing its emphasis; that is the safe direction to fail in.
public func normalizeSlackMarkdown(_ markdown: String) -> String {
    let wart = /(\*\*|__|~~)(\S[^\n]*?)([ \t]+)\1/
    return markdown.replacing(wart) { match in
        "\(match.output.1)\(match.output.2)\(match.output.1)\(match.output.3)"
    }
}

/// Pull Slack's markdown out of a raw `org.chromium.web-custom-data` payload, normalised and
/// ready to insert. Returns nil when the payload is absent or carries no markdown entry, so the
/// caller can fall back to the plain-text flavour.
public func slackMarkdown(fromWebCustomData data: Data) -> String? {
    guard let markdown = decodeWebCustomData(data)[slackMarkdownMIMEType], !markdown.isEmpty else {
        return nil
    }
    return normalizeSlackMarkdown(markdown)
}
