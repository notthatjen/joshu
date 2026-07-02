import Foundation
import GRDB

public enum ReviewStatus: String, Codable, Sendable {
    case queued, running, completed, failed, stale, cancelled
}

public enum FindingSeverity: String, Codable, CaseIterable, Sendable, Comparable {
    case blocker, high, medium, low, nit

    private var rank: Int {
        switch self {
        case .blocker: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        case .nit: 4
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public struct Finding: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var severity: FindingSeverity
    public var file: String
    public var line: Int?
    public var title: String
    public var detail: String

    enum CodingKeys: String, CodingKey {
        case severity, file, line, title, detail
    }
}

/// One review execution. History = all runs for the same (owner, repo, pr).
public struct ReviewRun: Codable, Identifiable, Hashable, Sendable,
    FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "review_run"

    public var id: UUID
    public var url: String
    public var owner: String
    public var repo: String
    public var prNumber: Int
    public var title: String
    public var author: String
    public var headSHA: String
    public var baseRef: String
    public var prState: String // OPEN / CLOSED / MERGED
    public var status: ReviewStatus
    public var findingsJSON: Data
    public var summary: String?
    public var promptVersion: Int
    public var errorMessage: String?
    public var createdAt: Date
    public var completedAt: Date?
    public var lastCheckedAt: Date?

    public var findings: [Finding] {
        (try? JSONDecoder().decode([Finding].self, from: findingsJSON)) ?? []
    }

    public var subjectKey: String { "\(owner)/\(repo)#\(prNumber)" }
}

public struct PRRef: Hashable, Sendable {
    public let owner: String
    public let repo: String
    public let number: Int
    public var url: String { "https://github.com/\(owner)/\(repo)/pull/\(number)" }

    /// Accepts full PR URLs (with optional trailing path/query junk).
    public static func parse(_ input: String) -> PRRef? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"github\.com/([\w.-]+)/([\w.-]+)/pull/(\d+)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
            let ownerRange = Range(match.range(at: 1), in: trimmed),
            let repoRange = Range(match.range(at: 2), in: trimmed),
            let numberRange = Range(match.range(at: 3), in: trimmed),
            let number = Int(trimmed[numberRange])
        else { return nil }
        return PRRef(
            owner: String(trimmed[ownerRange]),
            repo: String(trimmed[repoRange]),
            number: number)
    }
}

public enum FindingsPayload {
    /// Pull `{"summary": …, "findings": […]}` out of model output that may
    /// wrap it in prose or a ```json fence — the fallback when schema-mode
    /// output isn't clean JSON.
    public static func extract(from text: String) -> (summary: String?, findings: [Finding])? {
        for candidate in candidates(in: text) {
            guard let data = candidate.data(using: .utf8) else { continue }
            struct Payload: Decodable {
                var summary: String?
                var findings: [Finding]
            }
            if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
                return (payload.summary, payload.findings)
            }
        }
        return nil
    }

    private static func candidates(in text: String) -> [String] {
        var result = [text]
        // Fenced blocks first.
        for fence in ["```json", "```"] {
            if let start = text.range(of: fence),
               let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
                result.append(String(text[start.upperBound..<end.lowerBound]))
            }
        }
        // First { … last } as a last resort.
        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last {
            result.append(String(text[first...last]))
        }
        return result
    }
}
