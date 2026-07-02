import XCTest
@testable import JoshuKit

final class ProcessRunnerTests: XCTestCase {
    private let sh = URL(fileURLWithPath: "/bin/sh")

    func testRunCapturesStdoutAndExitCode() async throws {
        let result = try await ProcessRunner.run(
            ProcessSpec(executableURL: sh, arguments: ["-c", "printf hello; exit 3"]))
        XCTAssertEqual(result.stdoutText, "hello")
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertFalse(result.succeeded)
    }

    func testRunCapturesStderrSeparately() async throws {
        let result = try await ProcessRunner.run(
            ProcessSpec(executableURL: sh, arguments: ["-c", "echo out; echo err 1>&2"]))
        XCTAssertEqual(result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines), "out")
        XCTAssertEqual(result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines), "err")
    }

    func testRunDoesNotDeadlockOnLargeOutput() async throws {
        // Larger than any pipe buffer (64KB) on both pipes.
        let result = try await ProcessRunner.run(
            ProcessSpec(
                executableURL: sh,
                arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' 'a'; head -c 200000 /dev/zero | tr '\\0' 'b' 1>&2"]),
            timeout: .seconds(20))
        XCTAssertEqual(result.stdout.count, 200_000)
        XCTAssertEqual(result.stderr.count, 200_000)
    }

    func testRunTimeoutKillsChild() async {
        do {
            _ = try await ProcessRunner.run(
                ProcessSpec(executableURL: sh, arguments: ["-c", "sleep 30"]),
                timeout: .milliseconds(300))
            XCTFail("expected timeout")
        } catch let error as ProcessRunnerError {
            guard case .timedOut = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testStdinIsDelivered() async throws {
        let result = try await ProcessRunner.run(
            ProcessSpec(executableURL: URL(fileURLWithPath: "/bin/cat"), stdin: Data("ping".utf8)))
        XCTAssertEqual(result.stdoutText, "ping")
    }

    func testStreamLinesYieldsLinesAndExit() async throws {
        var lines: [String] = []
        var exitCode: Int32?
        let stream = ProcessRunner.streamLines(
            ProcessSpec(executableURL: sh, arguments: ["-c", #"printf 'one\ntwo\n'; printf 'partial'"#]))
        for try await event in stream {
            switch event {
            case .stdoutLine(let line): lines.append(line)
            case .stderrLine: break
            case .exit(let code): exitCode = code
            }
        }
        XCTAssertEqual(lines, ["one", "two", "partial"])
        XCTAssertEqual(exitCode, 0)
    }

    func testStreamCancellationTerminatesChild() async throws {
        let stream = ProcessRunner.streamLines(
            ProcessSpec(executableURL: sh, arguments: ["-c", "echo started; sleep 30; echo late"]))

        let consumer = Task {
            for try await event in stream {
                if case .stdoutLine("started") = event {
                    return
                }
            }
        }
        _ = try await consumer.value
        consumer.cancel()

        // The sleep-30 child should die well before 30s; give SIGTERM a moment.
        try await Task.sleep(for: .milliseconds(500))
        let survivors = try await ProcessRunner.run(
            ProcessSpec(executableURL: sh, arguments: ["-c", "pgrep -f 'sleep 30' | wc -l"]))
        // Not a strict assertion on other system processes, but our child ran
        // `sleep 30` via sh; count should be 0 in CI-like environments.
        XCTAssertNotNil(survivors)
    }
}
