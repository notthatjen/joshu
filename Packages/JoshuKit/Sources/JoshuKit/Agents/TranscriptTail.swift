import Foundation

/// Incremental JSONL reading: remember a byte offset, read only appended
/// bytes, and never consume a partial trailing line (the file is often
/// mid-write). Re-parsing whole multi-MB session files on every FSEvent is
/// how overlay apps melt laptops.
public enum TranscriptTail {
    public static func readNewLines(
        fileURL: URL, from offset: UInt64
    ) throws -> (lines: [String], newOffset: UInt64) {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        // File shrank (rotation/rewrite): start over.
        let start = offset <= size ? offset : 0
        try handle.seek(toOffset: start)
        let data = try handle.readToEnd() ?? Data()

        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
            return ([], start) // only a partial line so far
        }

        let complete = data[data.startIndex...lastNewline]
        let lines = complete
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        let consumed = UInt64(complete.count)
        return (lines, start + consumed)
    }
}
