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
            proc.terminate()
            proc.waitUntilExit()
        }
    }

    return try await withTaskCancellationHandler {
        logger.debug("Running \(executable) \(arguments.joined(separator: " "))")
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
