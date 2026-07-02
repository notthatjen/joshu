import XCTest
@testable import JoshuKit

/// Opt-in smoke against a real on-disk session file (machine-dependent, so
/// skipped unless JOSHU_REAL_CLAUDE_FIXTURE is set to a .jsonl path).
/// Run: JOSHU_REAL_CLAUDE_FIXTURE=~/.claude/projects/<slug>/<id>.jsonl swift test --filter RealSession
final class RealSessionSmokeTests: XCTestCase {
    func testParsesRealClaudeSessionWithoutDrift() throws {
        guard let raw = ProcessInfo.processInfo.environment["JOSHU_REAL_CLAUDE_FIXTURE"] else {
            throw XCTSkip("JOSHU_REAL_CLAUDE_FIXTURE not set")
        }
        let url = URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
        let data = try Data(contentsOf: url)

        let session = ClaudeTranscriptParser().parse(data: data)

        XCTAssertGreaterThan(session.messages.count, 0, "no messages parsed")
        XCTAssertNotNil(session.cwd)
        // Drift telemetry: unknown records are tolerated, but a real current
        // file producing many unknowns means our type list is stale.
        let lineCount = data.split(separator: UInt8(ascii: "\n")).count
        print("real fixture: \(lineCount) lines → \(session.messages.count) messages, " +
              "\(session.skippedRecords) skipped, \(session.unknownRecords) unknown, " +
              "title=\(session.title ?? "nil")")
        XCTAssertLessThan(Double(session.unknownRecords), Double(lineCount) * 0.2,
                          "over 20% unknown records — schema drifted, update the parser")
    }
}
