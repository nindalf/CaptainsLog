import Foundation
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "process")

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

public enum ProcessError: Error, LocalizedError {
    case timedOut
    case nonZeroExit(code: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Process timed out"
        case .nonZeroExit(let code, let stderr):
            return "Process exited with code \(code): \(stderr)"
        }
    }
}

private let defaultEnvironment: [String: String] = {
    var env = ProcessInfo.processInfo.environment
    let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
    if let existing = env["PATH"] {
        env["PATH"] = "\(extraPaths):\(existing)"
    } else {
        env["PATH"] = "\(extraPaths):/usr/bin:/bin"
    }
    return env
}()

/// The first executable called `name` on the PATH that `runProcess` gives its children.
public func findExecutable(_ name: String) -> String? {
    (defaultEnvironment["PATH"] ?? "").split(separator: ":")
        .map { "\($0)/\(name)" }
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

public func runProcess(
    _ executable: String,
    arguments: [String],
    environment: [String: String]? = nil,
    workingDirectory: URL? = nil,
    stdinData: Data? = nil,
    timeout: Duration = .seconds(30)
) async throws -> ProcessResult {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = arguments
    proc.environment = environment ?? defaultEnvironment
    if let workingDirectory {
        proc.currentDirectoryURL = workingDirectory
    }

    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = errPipe
    let exitContinuation = AsyncStream<Void>.makeStream()
    proc.terminationHandler = { _ in exitContinuation.continuation.finish() }

    if let stdinData {
        let inPipe = Pipe()
        proc.standardInput = inPipe
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try proc.run()
            try inPipe.fileHandleForWriting.write(contentsOf: stdinData)
            try inPipe.fileHandleForWriting.close()

            async let stdoutData = readToEnd(outPipe.fileHandleForReading)
            async let stderrData = readToEnd(errPipe.fileHandleForReading)
            async let exit: Void = waitForExit(
                proc, stream: exitContinuation.stream, timeout: timeout)

            try await exit
            let (out, err) = try await (stdoutData, stderrData)

            guard proc.terminationStatus == 0 else {
                let msg = String(data: err, encoding: .utf8) ?? "<binary>"
                throw ProcessError.nonZeroExit(code: proc.terminationStatus, stderr: msg)
            }
            return ProcessResult(exitCode: proc.terminationStatus, stdout: out, stderr: err)
        } onCancel: {
            guard proc.isRunning else { return }
            proc.terminate()
            proc.waitUntilExit()
        }
    }

    return try await withTaskCancellationHandler {
        logger.debug("Running \(executable) \(arguments.joined(separator: " "))")
        try Task.checkCancellation()
        try proc.run()

        async let stdoutData = readToEnd(outPipe.fileHandleForReading)
        async let stderrData = readToEnd(errPipe.fileHandleForReading)
        async let exit: Void = waitForExit(proc, stream: exitContinuation.stream, timeout: timeout)

        try await exit
        let (out, err) = try await (stdoutData, stderrData)

        guard proc.terminationStatus == 0 else {
            let msg = String(data: err, encoding: .utf8) ?? "<binary>"
            logger.error(
                "Process failed: \(executable) exit=\(proc.terminationStatus) stderr=\(msg)")
            throw ProcessError.nonZeroExit(code: proc.terminationStatus, stderr: msg)
        }
        return ProcessResult(exitCode: proc.terminationStatus, stdout: out, stderr: err)
    } onCancel: {
        // A task cancelled before the child launched calls this at once, and terminating it would raise.
        guard proc.isRunning else { return }
        proc.terminate()
        proc.waitUntilExit()
    }
}

/// Runs `executable` on this process's terminal, for a child that prompts the user (age asking for a passphrase).
/// `Process` starts its child in a new process group, and a background group that reads the terminal is stopped.
/// The child's output goes straight to the terminal, so there are no pipes to drain.
public func runInteractiveProcess(_ executable: String, arguments: [String]) async throws {
    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    let envp = defaultEnvironment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { (argv + envp).forEach { free($0) } }
    var pid: pid_t = 0
    let rc = posix_spawn(&pid, executable, nil, nil, argv, envp)
    guard rc == 0 else {
        throw ProcessError.nonZeroExit(code: rc, stderr: "Couldn't start \(executable): \(String(cString: strerror(rc)))")
    }
    let status = await Task.detached(priority: .utility) {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        return status
    }.value
    // WIFEXITED and WEXITSTATUS, which Swift doesn't import.
    let code = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
    guard code == 0 else {
        throw ProcessError.nonZeroExit(code: code, stderr: "\(URL(filePath: executable).lastPathComponent) exited with code \(code)")
    }
}

/// Runs `executable` until it exits, handing `onLine` each line of its stderr as it arrives, for a child
/// that waits on the user (gws printing a login link). `environment` is added to the usual one.
/// Cancelling terminates the child. Throws `nonZeroExit` with the stderr seen.
public func runWatchingStderr(
    _ executable: String,
    arguments: [String],
    environment: [String: String] = [:],
    timeout: Duration,
    onLine: @escaping @Sendable (String) -> Void
) async throws {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = arguments
    proc.environment = defaultEnvironment.merging(environment) { $1 }
    proc.standardInput = FileHandle.nullDevice
    proc.standardOutput = FileHandle.nullDevice
    let errPipe = Pipe()
    proc.standardError = errPipe
    let exitContinuation = AsyncStream<Void>.makeStream()
    proc.terminationHandler = { _ in exitContinuation.continuation.finish() }

    try await withTaskCancellationHandler {
        try Task.checkCancellation()
        try proc.run()
        let handle = errPipe.fileHandleForReading
        async let stderrText = Task.detached(priority: .utility) {
            var text = ""
            for try await line in handle.bytes.lines {
                onLine(line)
                text += line + "\n"
            }
            return text
        }.value
        async let exit: Void = waitForExit(proc, stream: exitContinuation.stream, timeout: timeout)

        try await exit
        let err = try await stderrText
        // Cancelling terminates the child, which isn't its failure.
        try Task.checkCancellation()
        guard proc.terminationStatus == 0 else {
            logger.error("Process failed: \(executable) exit=\(proc.terminationStatus) stderr=\(err)")
            throw ProcessError.nonZeroExit(code: proc.terminationStatus, stderr: err)
        }
    } onCancel: {
        guard proc.isRunning else { return }
        proc.terminate()
        proc.waitUntilExit()
    }
}

private func readToEnd(_ handle: FileHandle) async throws -> Data {
    try await Task.detached(priority: .utility) {
        try handle.readToEnd() ?? Data()
    }.value
}

private func waitForExit(_ proc: Process, stream: AsyncStream<Void>, timeout: Duration) async throws
{
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            for await _ in stream {}
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            if proc.isRunning {
                proc.terminate()
                throw ProcessError.timedOut
            }
        }
        try await group.next()
        group.cancelAll()
    }
}
