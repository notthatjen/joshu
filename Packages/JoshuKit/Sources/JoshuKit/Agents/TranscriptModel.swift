import Foundation

public enum AgentTool: String, Codable, Hashable, Sendable {
    case claude, codex
}

/// Not a bool: there are no lock files, so liveness is a heuristic and the
/// UI copy must hedge ("recently active").
public enum SessionLiveness: Hashable, Sendable {
    case historical
    case live
    case unknown
}

public enum TranscriptRole: String, Hashable, Sendable {
    case user, assistant, system, tool
}

public enum ContentBlock: Hashable, Sendable {
    case text(String)
    case thinking(String)
    case toolUse(name: String, summary: String)
    case toolResult(summary: String)
    /// Schema drift defense: unknown block/record types are preserved, never
    /// a parse failure.
    case unknown(type: String)
}

public struct TranscriptMessage: Identifiable, Hashable, Sendable {
    public let id: String
    public let role: TranscriptRole
    public let blocks: [ContentBlock]
    public let timestamp: Date?

    public init(id: String, role: TranscriptRole, blocks: [ContentBlock], timestamp: Date?) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.timestamp = timestamp
    }

    /// Concatenated visible text (no thinking/tool plumbing).
    public var plainText: String {
        blocks.compactMap {
            if case .text(let text) = $0 { return text }
            return nil
        }.joined(separator: "\n")
    }
}

public struct ParsedSession: Sendable {
    public var messages: [TranscriptMessage] = []
    public var title: String?
    public var cwd: String?
    public var sessionID: String?
    /// Drift counters, surfaced in the UI as "N unrecognized entries".
    public var skippedRecords = 0
    public var unknownRecords = 0

    public init() {}
}

/// One session file found on disk.
public struct DiscoveredSession: Identifiable, Hashable, Sendable {
    public let id: String
    public let tool: AgentTool
    public let title: String
    public let fileURL: URL
    public let cwd: String
    public let lastActivity: Date
    public var liveness: SessionLiveness

    public init(
        id: String, tool: AgentTool, title: String, fileURL: URL,
        cwd: String, lastActivity: Date, liveness: SessionLiveness = .unknown
    ) {
        self.id = id
        self.tool = tool
        self.title = title
        self.fileURL = fileURL
        self.cwd = cwd
        self.lastActivity = lastActivity
        self.liveness = liveness
    }
}
