import Foundation
import JoshuKit

public struct Worktree: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let branch: String?
    public let prunable: Bool

    public var displayName: String {
        branch ?? URL(fileURLWithPath: path).lastPathComponent
    }
}

enum CodingServices {
    /// `git worktree list --porcelain` → stanzas separated by blank lines:
    /// worktree <path> / HEAD <sha> / branch refs/heads/<name> / prunable …
    static func parseWorktrees(porcelain: String) -> [Worktree] {
        var result: [Worktree] = []
        var path: String?
        var branch: String?
        var prunable = false

        func flush() {
            if let path { result.append(Worktree(path: path, branch: branch, prunable: prunable)) }
            path = nil
            branch = nil
            prunable = false
        }

        for line in porcelain.components(separatedBy: .newlines) {
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch refs/heads/") {
                branch = String(line.dropFirst("branch refs/heads/".count))
            } else if line.hasPrefix("prunable") {
                prunable = true
            }
        }
        flush()
        return result
    }

    static func listWorktrees(repoPath: String, git: URL) async throws -> [Worktree] {
        let result = try await ProcessRunner.run(
            ProcessSpec(
                executableURL: git,
                arguments: ["worktree", "list", "--porcelain"],
                workingDirectory: URL(fileURLWithPath: repoPath)),
            timeout: .seconds(20))
        guard result.succeeded else {
            throw CodingError.git(result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parseWorktrees(porcelain: result.stdoutText)
    }

    // MARK: - Claude discovery

    static func discoverClaudeSessions(worktreePath: String) -> [DiscoveredSession] {
        let directory = ClaudeSessionPaths.projectDirectory(for: worktreePath)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }

        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url in
                let id = url.deletingPathExtension().lastPathComponent
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let title = claudeSessionTitle(fileURL: url) ?? "Session \(id.prefix(8))"
                return DiscoveredSession(
                    id: id, tool: .claude, title: title, fileURL: url,
                    cwd: worktreePath, lastActivity: modified,
                    liveness: livenessByRecency(modified))
            }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Title lives in an `ai-title` record. Scan a bounded head chunk — good
    /// enough without re-reading multi-MB transcripts during discovery.
    private static func claudeSessionTitle(fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256 * 1024) else { return nil }

        for lineData in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            // Cheap pre-filter before JSON decoding.
            guard lineData.count < 4096 else { continue }
            let line = String(decoding: lineData, as: UTF8.self)
            guard line.contains("\"ai-title\"") else { continue }
            if let record = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
               let title = record["aiTitle"] as? String {
                return title
            }
        }
        return nil
    }

    // MARK: - Codex discovery

    /// First-line session_meta cwd, cached per path (immutable once written).
    private static let codexMetaCache = Locked<[String: (cwd: String?, id: String?)]>([:])

    static func discoverCodexSessions(
        worktreePath: String,
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    ) -> [DiscoveredSession] {
        let sessionsDir = codexHome.appendingPathComponent("sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }

        let titles = codexIndexTitles(codexHome: codexHome)
        let liveIDs = codexLiveSessionIDs(codexHome: codexHome)

        var sessions: [DiscoveredSession] = []
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("rollout-") {
            let meta: (cwd: String?, id: String?)
            if let cached = codexMetaCache.value[url.path] {
                meta = cached
            } else {
                meta = CodexTranscriptParser.sessionMeta(fileURL: url) ?? (nil, nil)
                codexMetaCache.mutate { $0[url.path] = meta }
            }
            guard meta.cwd == worktreePath, let id = meta.id else { continue }

            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let liveness: SessionLiveness = liveIDs.contains(id) ? .live : livenessByRecency(modified)
            sessions.append(DiscoveredSession(
                id: id, tool: .codex,
                title: titles[id] ?? "Codex \(id.suffix(6))",
                fileURL: url, cwd: worktreePath,
                lastActivity: modified, liveness: liveness))
        }
        return sessions.sorted { $0.lastActivity > $1.lastActivity }
    }

    private static func codexIndexTitles(codexHome: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: codexHome.appendingPathComponent("session_index.jsonl"))
        else { return [:] }
        var titles: [String: String] = [:]
        for lineData in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            if let record = (try? JSONSerialization.jsonObject(with: Data(lineData))) as? [String: Any],
               let id = record["id"] as? String,
               let name = record["thread_name"] as? String {
                titles[id] = name
            }
        }
        return titles
    }

    /// ~/.codex/process_manager/chat_processes.json tracks running chats —
    /// the one authoritative liveness signal we have.
    private static func codexLiveSessionIDs(codexHome: URL) -> Set<String> {
        guard let data = try? Data(
            contentsOf: codexHome.appendingPathComponent("process_manager/chat_processes.json")),
            let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }
        var ids: Set<String> = []
        for entry in array {
            for key in ["session_id", "sessionId", "id", "thread_id"] {
                if let id = entry[key] as? String { ids.insert(id) }
            }
        }
        return ids
    }

    // MARK: - Liveness

    /// No lock files exist for either tool — recency of appends is the
    /// primary heuristic (hence "recently active" copy in the UI).
    static func livenessByRecency(_ lastActivity: Date, window: TimeInterval = 45) -> SessionLiveness {
        Date().timeIntervalSince(lastActivity) < window ? .live : .historical
    }
}

public enum CodingError: Error, LocalizedError {
    case git(String)
    case toolMissing(String)

    public var errorDescription: String? {
        switch self {
        case .git(let message): "git: \(message)"
        case .toolMissing(let tool): "\(tool) not found — install it or check PATH"
        }
    }
}

/// Tiny lock box for static caches.
final class Locked<Value>: @unchecked Sendable {
    private var storage: Value
    private let lock = NSLock()

    init(_ value: Value) { storage = value }

    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&storage)
    }
}
