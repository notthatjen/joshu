import Foundation
import JoshuKit

/// Extracts action items from a transcript via headless claude with a JSON
/// schema. Pure JSON-shaping lives in `parse` so it's unit-testable without
/// spawning claude.
public enum ActionItemExtractor {
    public static let schema = #"{"type":"object","properties":{"actionItems":{"type":"array","items":{"type":"object","properties":{"text":{"type":"string"},"owner":{"type":["string","null"]},"isImmediate":{"type":"boolean"},"suggestedPrompt":{"type":["string","null"]}},"required":["text","isImmediate"]}}},"required":["actionItems"]}"#

    public static func extract(
        transcript: String, meetingTitle: String, claude: URL
    ) async throws -> [ActionItem] {
        let prompt = """
        Extract action items from this meeting transcript. For each: the task \
        text; the owner if named (else null); isImmediate=true only if it \
        should be started right now (not someday/maybe); and when it's a \
        coding/engineering task, a suggestedPrompt an AI coding agent could \
        run to do it (else null).

        Respond with ONLY JSON: {"actionItems":[{"text","owner","isImmediate","suggestedPrompt"}]}.

        MEETING: \(meetingTitle)
        TRANSCRIPT:
        \(transcript)
        """

        for arguments in [
            ["-p", prompt, "--output-format", "json", "--json-schema", schema,
             "--permission-mode", "dontAsk", "--allowedTools", ""],
            ["-p", prompt, "--output-format", "json",
             "--permission-mode", "dontAsk", "--allowedTools", ""],
        ] {
            let result = try await ProcessRunner.run(
                ProcessSpec(executableURL: claude, arguments: arguments),
                timeout: .seconds(300))
            if result.succeeded, let items = parse(claudeEnvelope: result.stdout) {
                return items
            }
        }
        return []
    }

    /// Pull actionItems out of the `claude --output-format json` envelope,
    /// tolerating structured_output, a JSON `result` string, or fenced JSON.
    static func parse(claudeEnvelope data: Data) -> [ActionItem]? {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return parseActionItems(text: String(decoding: data, as: UTF8.self)) }

        if let structured = envelope["structured_output"],
           let structuredData = try? JSONSerialization.data(withJSONObject: structured),
           let items = decode(structuredData) {
            return items
        }
        if let text = envelope["result"] as? String {
            return parseActionItems(text: text)
        }
        return nil
    }

    static func parseActionItems(text: String) -> [ActionItem]? {
        for candidate in candidates(in: text) {
            if let data = candidate.data(using: .utf8), let items = decode(data) {
                return items
            }
        }
        return nil
    }

    private static func decode(_ data: Data) -> [ActionItem]? {
        struct Payload: Decodable { var actionItems: [ActionItem] }
        return (try? JSONDecoder().decode(Payload.self, from: data))?.actionItems
    }

    private static func candidates(in text: String) -> [String] {
        var result = [text]
        if let start = text.range(of: "```json") ?? text.range(of: "```"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            result.append(String(text[start.upperBound..<end.lowerBound]))
        }
        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last {
            result.append(String(text[first...last]))
        }
        return result
    }
}
