import Foundation

public struct ProcessSpec: Sendable {
    /// Resolved absolute path — never a bare name (GUI apps don't get the
    /// user's shell PATH; see ToolAvailability).
    public var executableURL: URL
    public var arguments: [String]
    public var workingDirectory: URL?
    /// Merged over the inherited environment.
    public var environment: [String: String]
    public var stdin: Data?

    public init(
        executableURL: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        stdin: Data? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.stdin = stdin
    }
}

public struct ProcessResult: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
    public var succeeded: Bool { exitCode == 0 }
}

public enum ProcessEvent: Sendable {
    case stdoutLine(String)
    case stderrLine(String)
    case exit(Int32)
}

public enum ProcessRunnerError: Error, Sendable {
    case timedOut
    case launchFailed(String)
}

/// The one external-process utility. Two shapes: one-shot (`run`) for
/// git/gh/probes, streaming (`streamLines`) for `claude -p --output-format
/// stream-json` and `codex exec --json`.
public enum ProcessRunner {
    // MARK: - One-shot

    public static func run(_ spec: ProcessSpec, timeout: Duration? = nil) async throws -> ProcessResult {
        let process = try makeProcess(spec)
        let stdoutPipe = process.standardOutput as! Pipe
        let stderrPipe = process.standardError as! Pipe

        // Drain both pipes concurrently — synchronous sequential reads
        // deadlock when the child fills the other pipe's buffer.
        async let stdout = readAll(stdoutPipe)
        async let stderr = readAll(stderrPipe)

        try launch(process, stdin: spec.stdin)

        let exitCode: Int32 = try await withThrowingTaskGroup(of: Int32?.self) { group in
            group.addTask {
                await waitForExit(process)
            }
            if let timeout {
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return nil
                }
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let code = first else {
                terminate(process)
                throw ProcessRunnerError.timedOut
            }
            return code
        }

        return ProcessResult(stdout: await stdout, stderr: await stderr, exitCode: exitCode)
    }

    // MARK: - Streaming

    /// Line-oriented event stream. Cancelling the consuming task terminates
    /// the child (SIGTERM, then SIGKILL after a grace period).
    public static func streamLines(_ spec: ProcessSpec) -> AsyncThrowingStream<ProcessEvent, Error> {
        AsyncThrowingStream { continuation in
            let process: Process
            do {
                process = try makeProcess(spec)
            } catch {
                continuation.finish(throwing: error)
                return
            }
            let stdoutPipe = process.standardOutput as! Pipe
            let stderrPipe = process.standardError as! Pipe

            let stdoutBuffer = LineBuffer { continuation.yield(.stdoutLine($0)) }
            let stderrBuffer = LineBuffer { continuation.yield(.stderrLine($0)) }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    stdoutBuffer.flush()
                } else {
                    stdoutBuffer.append(data)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    stderrBuffer.flush()
                } else {
                    stderrBuffer.append(data)
                }
            }

            process.terminationHandler = { process in
                // Give the readability handlers a beat to drain the tail.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                    stdoutBuffer.flush()
                    stderrBuffer.flush()
                    continuation.yield(.exit(process.terminationStatus))
                    continuation.finish()
                }
            }

            continuation.onTermination = { reason in
                if case .cancelled = reason {
                    terminate(process)
                }
            }

            do {
                try launch(process, stdin: spec.stdin)
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Internals

    private static func makeProcess(_ spec: ProcessSpec) throws -> Process {
        let process = Process()
        process.executableURL = spec.executableURL
        process.arguments = spec.arguments
        process.currentDirectoryURL = spec.workingDirectory
        process.environment = ProcessInfo.processInfo.environment
            .merging(spec.environment) { _, new in new }
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.standardInput = spec.stdin != nil ? Pipe() : FileHandle.nullDevice
        return process
    }

    private static func launch(_ process: Process, stdin: Data?) throws {
        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }
        if let stdin, let pipe = process.standardInput as? Pipe {
            pipe.fileHandleForWriting.write(stdin)
            pipe.fileHandleForWriting.closeFile()
        }
    }

    private static func waitForExit(_ process: Process) async -> Int32 {
        await withCheckedContinuation { continuation in
            if !process.isRunning, process.processIdentifier != 0 {
                continuation.resume(returning: process.terminationStatus)
                return
            }
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }

    /// SIGTERM, then SIGKILL if the child ignores it. Best-effort: children
    /// of the child (claude's own tool processes) are its job to reap.
    static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    private static func readAll(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }
    }
}

/// Splits a byte stream into lines, tolerating a partial trailing line
/// (JSONL files/pipes are often mid-write).
private final class LineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            lines.append(String(decoding: line, as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        lock.unlock()
        for line in lines where !line.isEmpty {
            onLine(line)
        }
    }

    func flush() {
        lock.lock()
        let remainder = buffer
        buffer.removeAll()
        lock.unlock()
        if !remainder.isEmpty {
            onLine(String(decoding: remainder, as: UTF8.self))
        }
    }
}
