import Foundation

/// Parses Claude Code session JSONL (~/.claude/projects/<slug>/<uuid>.jsonl).
///
/// Schema (verified on-disk 2026-07-02, unversioned — decode tolerantly):
/// - `user`/`assistant` records: `message.role`, `message.content` (string
///   for plain user turns; array of `{type: thinking|text|tool_use|
///   tool_result}` blocks otherwise), `uuid`, `timestamp`, `isSidechain`
/// - `ai-title` record: `aiTitle`
/// - `last-prompt`, `queue-operation`, `attachment`, `file-history-snapshot`,
///   … : metadata, not rendered
public struct ClaudeTranscriptParser: Sendable {
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

        switch record["type"] as? String {
        case "user", "assistant":
            // Sub-agent branches don't belong in the linear transcript.
            if record["isSidechain"] as? Bool == true {
                session.skippedRecords += 1
                return
            }
            if session.cwd == nil { session.cwd = record["cwd"] as? String }
            if session.sessionID == nil { session.sessionID = record["sessionId"] as? String }
            if let message = parseMessage(record) {
                session.messages.append(message)
            } else {
                session.skippedRecords += 1
            }
        case "ai-title":
            session.title = record["aiTitle"] as? String ?? session.title
        case "last-prompt", "queue-operation", "attachment", "file-history-snapshot",
             "mode", "permission-mode", "worktree-state", "bridge-session", "pr-link",
             "system":
            session.skippedRecords += 1
        case .some(let unknownType):
            _ = unknownType
            session.unknownRecords += 1
        case nil:
            session.unknownRecords += 1
        }
    }

    private func parseMessage(_ record: [String: Any]) -> TranscriptMessage? {
        guard let message = record["message"] as? [String: Any] else { return nil }

        let roleString = message["role"] as? String ?? record["type"] as? String ?? "user"
        var role = TranscriptRole(rawValue: roleString) ?? .user

        var blocks: [ContentBlock] = []
        if let text = message["content"] as? String {
            blocks = [.text(text)]
        } else if let content = message["content"] as? [[String: Any]] {
            blocks = content.map(parseBlock)
            // Records that are purely tool plumbing render as compact tool rows.
            if role == .user, blocks.allSatisfy({
                if case .toolResult = $0 { return true }
                return false
            }), !blocks.isEmpty {
                role = .tool
            }
        }

        guard !blocks.isEmpty else { return nil }

        let timestamp = (record["timestamp"] as? String).flatMap(Self.parseDate)
        let id = record["uuid"] as? String ?? UUID().uuidString
        return TranscriptMessage(id: id, role: role, blocks: blocks, timestamp: timestamp)
    }

    private func parseBlock(_ block: [String: Any]) -> ContentBlock {
        switch block["type"] as? String {
        case "text":
            return .text(block["text"] as? String ?? "")
        case "thinking":
            return .thinking(block["thinking"] as? String ?? "")
        case "tool_use":
            let name = block["name"] as? String ?? "tool"
            let summary = (block["input"] as? [String: Any])
                .flatMap { input -> String? in
                    // Most tools have one obvious headline parameter.
                    for key in ["command", "file_path", "pattern", "prompt", "description", "url"] {
                        if let value = input[key] as? String { return value }
                    }
                    return nil
                } ?? ""
            return .toolUse(name: name, summary: String(summary.prefix(140)))
        case "tool_result":
            let summary: String
            if let text = block["content"] as? String {
                summary = text
            } else if let parts = block["content"] as? [[String: Any]] {
                summary = parts.compactMap { $0["text"] as? String }.joined(separator: " ")
            } else {
                summary = ""
            }
            return .toolResult(summary: String(summary.prefix(200)))
        case .some(let type):
            return .unknown(type: type)
        case nil:
            return .unknown(type: "?")
        }
    }

    static func parseDate(_ string: String) -> Date? {
        ISO8601DateFormatter.withFractional.date(from: string)
            ?? ISO8601DateFormatter.plain.date(from: string)
    }
}

extension ISO8601DateFormatter {
    public static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static let plain = ISO8601DateFormatter()
}
