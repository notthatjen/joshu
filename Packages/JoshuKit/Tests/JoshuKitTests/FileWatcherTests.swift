import XCTest
@testable import JoshuKit

final class FileWatcherTests: XCTestCase {
    func testDetectsFileAppendInWatchedDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("joshu-fw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("session.jsonl")
        try Data("line1\n".utf8).write(to: file)

        let watcher = FileWatcher(paths: [dir], latency: 0.1)
        defer { watcher.stop() }

        // Write after a short delay so the stream is definitely started.
        Task.detached {
            try? await Task.sleep(for: .milliseconds(300))
            if let handle = try? FileHandle(forWritingTo: file) {
                _ = try? handle.seekToEnd()
                handle.write(Data("line2\n".utf8))
                try? handle.close()
            }
        }

        let deadline = Task {
            try await Task.sleep(for: .seconds(10))
        }
        var sawChange = false
        for await changed in watcher.events {
            if changed.contains(where: { $0.path.hasPrefix(dir.path) || $0.path.contains("session.jsonl") }) {
                sawChange = true
                break
            }
            if deadline.isCancelled { break }
        }
        deadline.cancel()
        XCTAssertTrue(sawChange, "expected an FSEvents change for the appended file")
    }
}
