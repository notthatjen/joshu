import Foundation

/// Parses Codex rollout JSONL
/// (~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl).
///
/// Schema (verified on-disk 2026-07-02): every line is
/// `{timestamp, type, payload}`. Line 1 is `session_meta`
/// (`payload.cwd`, `payload.id`). Conversation lines are `response_item`
/// with `payload.type == "message"`, `payload.role` in
/// user|assistant|developer, `payload.content` = array of
/// `{type: input_text|output_text, text}`. `developer` role is injected
/// permissions/apps boilerplate — skipped.
public struct CodexTranscriptParser: Sendable {
    public init() {}

    public func parse(data: Data) -> ParsedSession {
        var session = ParsedSession()
        for lineData in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            parseLine(String(decoding: lineData, as: UTF8.self), into: &session)
        }
        return session
    }

    public func parseLine(_ line: String, into session: inout ParsedSession) {
        guard
            let data = line.data(using: .utf8),
            let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            session.skippedRecords += 1
            return
        }

        let payload = record["payload"] as? [String: Any] ?? [:]

        switch record["type"] as? String {
        case "session_meta":
            session.cwd = payload["cwd"] as? String
            session.sessionID = payload["id"] as? String
        case "response_item":
            guard payload["type"] as? String == "message" else {
                session.skippedRecords += 1
                return
            }
            let roleString = payload["role"] as? String ?? "user"
            // Injected permission/apps preamble, not conversation.
            guard roleString != "developer" else {
                session.skippedRecords += 1
                return
            }
            let role = TranscriptRole(rawValue: roleString) ?? .user

            let content = payload["content"] as? [[String: Any]] ?? []
            let blocks: [ContentBlock] = content.map { part in
                switch part["type"] as? String {
                case "input_text", "output_text":
                    return .text(part["text"] as? String ?? "")
                case .some(let type):
                    return .unknown(type: type)
                case nil:
                    return .unknown(type: "?")
                }
            }
            guard !blocks.isEmpty else {
                session.skippedRecords += 1
                return
            }

            let timestamp = (record["timestamp"] as? String).flatMap(ClaudeTranscriptParser.parseDate)
            let id = "\(record["timestamp"] as? String ?? UUID().uuidString)-\(session.messages.count)"
            session.messages.append(
                TranscriptMessage(id: id, role: role, blocks: blocks, timestamp: timestamp))
        case "event_msg", "turn_context", "compacted":
            session.skippedRecords += 1
        case .some:
            session.unknownRecords += 1
        case nil:
            session.unknownRecords += 1
        }
    }

    /// Cheap cwd probe: only the first line matters.
    public static func sessionMeta(fileURL: URL) -> (cwd: String?, id: String?)? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16 * 1024) else { return nil }
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
        let firstLine = data[data.startIndex..<newline]
        guard
            let record = (try? JSONSerialization.jsonObject(with: firstLine)) as? [String: Any],
            record["type"] as? String == "session_meta",
            let payload = record["payload"] as? [String: Any]
        else { return nil }
        return (payload["cwd"] as? String, payload["id"] as? String)
    }
}
