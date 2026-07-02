import XCTest
@testable import JoshuKit

final class ClaudeTranscriptParserTests: XCTestCase {
    private let parser = ClaudeTranscriptParser()

    private let fixture = """
    {"type":"user","uuid":"u1","timestamp":"2026-07-01T10:00:00.000Z","cwd":"/tmp/repo","sessionId":"s1","isSidechain":false,"message":{"role":"user","content":"hello there"}}
    {"type":"assistant","uuid":"a1","timestamp":"2026-07-01T10:00:05.000Z","isSidechain":false,"message":{"role":"assistant","content":[{"type":"thinking","thinking":"pondering"},{"type":"text","text":"hi!"},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls -la"}}]}}
    {"type":"user","uuid":"u2","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"total 8"}]}}
    {"type":"assistant","uuid":"a2","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"sidechain noise"}]}}
    {"type":"ai-title","aiTitle":"Fix the auth bug","sessionId":"s1"}
    {"type":"last-prompt","lastPrompt":"whatever","sessionId":"s1"}
    """

    func testParsesRealShapedRecords() {
        let session = parser.parse(data: Data(fixture.utf8))

        XCTAssertEqual(session.title, "Fix the auth bug")
        XCTAssertEqual(session.cwd, "/tmp/repo")
        XCTAssertEqual(session.sessionID, "s1")
        XCTAssertEqual(session.messages.count, 3) // sidechain excluded

        XCTAssertEqual(session.messages[0].role, .user)
        XCTAssertEqual(session.messages[0].plainText, "hello there")

        let assistant = session.messages[1]
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.blocks.count, 3)
        guard case .thinking = assistant.blocks[0],
              case .text("hi!") = assistant.blocks[1],
              case .toolUse(let name, let summary) = assistant.blocks[2] else {
            return XCTFail("unexpected blocks: \(assistant.blocks)")
        }
        XCTAssertEqual(name, "Bash")
        XCTAssertEqual(summary, "ls -la")

        // Pure tool_result user record renders as a tool row.
        XCTAssertEqual(session.messages[2].role, .tool)
    }

    func testDriftUnknownRecordTypeCountedNotFatal() {
        let drifted = fixture + "\n" + #"{"type":"hologram-v9","data":{"x":1}}"#
        let session = parser.parse(data: Data(drifted.utf8))
        XCTAssertEqual(session.unknownRecords, 1)
        XCTAssertEqual(session.messages.count, 3)
    }

    func testDriftMalformedLineSkipsLineNotFile() {
        let drifted = "not json at all {{{\n" + fixture
        let session = parser.parse(data: Data(drifted.utf8))
        XCTAssertEqual(session.skippedRecords, 3) // malformed + sidechain + last-prompt
        XCTAssertEqual(session.messages.count, 3)
    }

    func testDriftUnknownBlockTypePreserved() {
        let line = #"{"type":"assistant","uuid":"a9","isSidechain":false,"message":{"role":"assistant","content":[{"type":"quantum_block","payload":1},{"type":"text","text":"still here"}]}}"#
        var session = ParsedSession()
        parser.parseLine(line, into: &session)
        XCTAssertEqual(session.messages.count, 1)
        guard case .unknown(let type) = session.messages[0].blocks[0] else {
            return XCTFail("expected unknown block")
        }
        XCTAssertEqual(type, "quantum_block")
    }

    func testMissingOptionalFieldsNeverFail() {
        let line = #"{"type":"user","message":{"role":"user","content":"bare minimum"}}"#
        var session = ParsedSession()
        parser.parseLine(line, into: &session)
        XCTAssertEqual(session.messages.count, 1)
        XCTAssertNil(session.messages[0].timestamp)
    }
}

final class CodexTranscriptParserTests: XCTestCase {
    private let parser = CodexTranscriptParser()

    private let fixture = """
    {"timestamp":"2026-06-10T18:01:54.000Z","type":"session_meta","payload":{"id":"019e-abc","cwd":"/tmp/repo","cli_version":"0.5.0"}}
    {"timestamp":"2026-06-10T18:02:10.000Z","type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"<permissions instructions>stuff</permissions instructions>"}]}}
    {"timestamp":"2026-06-10T18:02:12.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"add a test"}]}}
    {"timestamp":"2026-06-10T18:02:20.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"done, added"}]}}
    {"timestamp":"2026-06-10T18:02:21.000Z","type":"event_msg","payload":{"type":"task_started"}}
    """

    func testParsesRealShapedRecords() {
        let session = parser.parse(data: Data(fixture.utf8))

        XCTAssertEqual(session.cwd, "/tmp/repo")
        XCTAssertEqual(session.sessionID, "019e-abc")
        // developer preamble + event_msg skipped
        XCTAssertEqual(session.messages.count, 2)
        XCTAssertEqual(session.messages[0].role, .user)
        XCTAssertEqual(session.messages[0].plainText, "add a test")
        XCTAssertEqual(session.messages[1].role, .assistant)
        XCTAssertEqual(session.messages[1].plainText, "done, added")
    }

    func testDriftUnknownTypesCounted() {
        let drifted = fixture + "\n" + #"{"timestamp":"2026-06-10T18:03:00.000Z","type":"new_fangled","payload":{}}"#
        let session = parser.parse(data: Data(drifted.utf8))
        XCTAssertEqual(session.unknownRecords, 1)
        XCTAssertEqual(session.messages.count, 2)
    }
}

final class ClaudeSessionPathsTests: XCTestCase {
    func testSlugReplacesSlashesAndDots() {
        // Verified real example: /. becomes -- (dot is replaced too).
        XCTAssertEqual(
            ClaudeSessionPaths.projectSlug(for: "/Users/x/sherpa-app/.claude/worktrees/demo"),
            "-Users-x-sherpa-app--claude-worktrees-demo")
    }
}

final class TranscriptTailTests: XCTestCase {
    func testIncrementalReadLeavesPartialLine() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("{\"a\":1}\n{\"b\":2}\n{\"part".utf8).write(to: url)
        let first = try TranscriptTail.readNewLines(fileURL: url, from: 0)
        XCTAssertEqual(first.lines, ["{\"a\":1}", "{\"b\":2}"])

        // Complete the partial line and append another.
        let handle = try FileHandle(forWritingTo: url)
        _ = try handle.seekToEnd()
        handle.write(Data("ial\":3}\n".utf8))
        try handle.close()

        let second = try TranscriptTail.readNewLines(fileURL: url, from: first.newOffset)
        XCTAssertEqual(second.lines, ["{\"partial\":3}"])

        let third = try TranscriptTail.readNewLines(fileURL: url, from: second.newOffset)
        XCTAssertEqual(third.lines, [])
    }
}
