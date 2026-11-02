// Records the sandbox app's windows (or the whole display) to a .mov at 2x, for the promo video.
// Runs until SIGTERM (or SIGINT in the foreground; background jobs ignore SIGINT), then finishes the file. Needs Screen Recording permission.
//   record <out.mov> [--display] [--pid N] [--no-cursor]
// Without --display it records the region of the app's main window, compositing only that
// app's windows, so other apps never appear. --display records the whole display (Quick Entry).

import AppKit
import AVFoundation
import ScreenCaptureKit

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let env = ProcessInfo.processInfo.environment
let cwd = URL(filePath: FileManager.default.currentDirectoryPath)
let appURL = URL(filePath: env["UI_APP"] ?? cwd.appending(path: ".build/ui-claude/Captain's Log.app").path(percentEncoded: false))

func sandboxPID() -> pid_t? {
    let target = appURL.resolvingSymlinksInPath().path(percentEncoded: false)
    return NSWorkspace.shared.runningApplications.first {
        $0.bundleURL?.resolvingSymlinksInPath().path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            == target.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }?.processIdentifier
}

final class Delegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    let finished = DispatchSemaphore(value: 0)
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { finished.signal() }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        FileHandle.standardError.write(Data("record: \(error)\n".utf8))
        finished.signal()
    }
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        FileHandle.standardError.write(Data("record: stream stopped: \(error)\n".utf8))
        finished.signal()
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let outPath = args.first(where: { !$0.hasPrefix("--") && Int($0) == nil }) else {
    FileHandle.standardError.write(Data("usage: record <out.mov> [--display] [--pid N] [--no-cursor]\n".utf8))
    exit(2)
}
let wholeDisplay = args.contains("--display")
let explicitPID = args.firstIndex(of: "--pid").flatMap { i in i + 1 < args.count ? pid_t(args[i + 1]) : nil }

do {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let filter: SCContentFilter
    let rect: CGRect
    let display: SCDisplay
    if wholeDisplay {
        guard let d = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else { throw Failure("no display") }
        display = d
        filter = SCContentFilter(display: d, excludingWindows: [])
        rect = CGRect(origin: .zero, size: d.frame.size)
    } else {
        guard let pid = explicitPID ?? sandboxPID() else { throw Failure("sandbox app not running") }
        let ours = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer != Int(CGWindowLevelForKey(.statusWindow)) && $0.frame.width > 1
        }
        guard let main = ours.filter({ $0.windowLayer == 0 }).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        else { throw Failure("no on-screen window for pid \(pid)") }
        guard let d = content.displays.first(where: { $0.frame.contains(CGPoint(x: main.frame.midX, y: main.frame.midY)) }) ?? content.displays.first
        else { throw Failure("no display") }
        display = d
        // Every window of the app, so popovers and sheets that appear later are included too.
        filter = SCContentFilter(display: d, including: content.applications.filter { $0.processID == pid }, exceptingWindows: [])
        // Exactly the main window: a margin picks up the app's other windows behind it.
        rect = main.frame.offsetBy(dx: -d.frame.minX, dy: -d.frame.minY)
            .intersection(CGRect(origin: .zero, size: d.frame.size))
    }
    let scale = CGFloat(filter.pointPixelScale)
    let config = SCStreamConfiguration()
    config.sourceRect = rect
    config.width = Int(rect.width * scale) & ~1
    config.height = Int(rect.height * scale) & ~1
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.showsCursor = !args.contains("--no-cursor")
    config.capturesAudio = false
    config.backgroundColor = .clear
    config.queueDepth = 8

    let url = URL(filePath: outPath)
    try? FileManager.default.removeItem(at: url)
    let recConfig = SCRecordingOutputConfiguration()
    recConfig.outputURL = url
    recConfig.outputFileType = .mov
    recConfig.videoCodecType = .hevc

    let delegate = Delegate()
    let stream = SCStream(filter: filter, configuration: config, delegate: delegate)
    let output = SCRecordingOutput(configuration: recConfig, delegate: delegate)
    try stream.addRecordingOutput(output)
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
        stream.startCapture { error in if let error { c.resume(throwing: error) } else { c.resume() } }
    }
    print("recording \(config.width)x\(config.height) px from \(Int(rect.minX)),\(Int(rect.minY)) pt on display \(display.displayID) to \(url.path(percentEncoded: false))")
    fflush(stdout)

    let stop = DispatchSemaphore(value: 0)
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler { stop.signal() }
        source.resume()
        objc_setAssociatedObject(stream, "\(sig)", source, .OBJC_ASSOCIATION_RETAIN)
    }
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async { stop.wait(); c.resume() }
    }
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
        stream.stopCapture { error in if let error { c.resume(throwing: error) } else { c.resume() } }
    }
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async { _ = delegate.finished.wait(timeout: .now() + 10); c.resume() }
    }
    print("saved \(url.path(percentEncoded: false))")
} catch {
    FileHandle.standardError.write(Data("record: \(error)\n".utf8))
    exit(1)
}
