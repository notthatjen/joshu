import Foundation
import Observation
import JoshuKit
import os

/// Runs AI reviews: gh metadata + diff → headless claude with a JSON schema
/// → persisted ReviewRun. Bounded concurrency, staleness via head SHA.
@MainActor
@Observable
final class ReviewerEngine {
    static let promptVersion = 1
    private static let maxConcurrent = 2
    private static let maxDiffBytes = 400_000

    private(set) var runs: [ReviewRun] = []
    private(set) var errorText: String?
    private(set) var runningCount = 0

    @ObservationIgnored private let store: ReviewStore
    @ObservationIgnored private let logger = Logger(subsystem: "com.wren.joshu", category: "Reviewer")
    @ObservationIgnored private var stalenessTimer: Task<Void, Never>?

    init(store: ReviewStore) {
        self.store = store
        reload()
        stalenessTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await self?.refreshStaleness()
            }
        }
    }

    deinit {
        stalenessTimer?.cancel()
    }

    private func reload() {
        runs = (try? store.latestPerSubject()) ?? []
    }

    // MARK: - Start / rerun

    func startReview(urlText: String) {
        guard let ref = PRRef.parse(urlText) else {
            errorText = "Not a GitHub PR URL"
            return
        }
        errorText = nil
        Task { await run(ref: ref) }
    }

    func rerun(_ run: ReviewRun) {
        let ref = PRRef(owner: run.owner, repo: run.repo, number: run.prNumber)
        Task { await self.run(ref: ref) }
    }

    private func run(ref: PRRef) async {
        guard runningCount < Self.maxConcurrent else {
            errorText = "Review queue full — wait for a run to finish"
            return
        }
        runningCount += 1
        defer { runningCount -= 1 }

        guard let gh = await sharedToolAvailability.url(for: .gh) else {
            errorText = "gh CLI not found — brew install gh"
            return
        }
        if case .unauthenticated = await sharedToolAvailability.status(for: .gh) {
            errorText = "gh not authenticated — run `gh auth login`"
            return
        }
        guard let claude = await sharedToolAvailability.url(for: .claude) else {
            errorText = "claude CLI not found"
            return
        }

        var record = ReviewRun(
            id: UUID(), url: ref.url, owner: ref.owner, repo: ref.repo,
            prNumber: ref.number, title: "\(ref.owner)/\(ref.repo)#\(ref.number)",
            author: "", headSHA: "", baseRef: "", prState: "OPEN",
            status: .running, findingsJSON: Data("[]".utf8), summary: nil,
            promptVersion: Self.promptVersion, errorMessage: nil,
            createdAt: Date(), completedAt: nil, lastCheckedAt: Date())
        persist(record)

        do {
            // Metadata
            let meta = try await ghJSON(
                gh: gh, ref: ref,
                fields: "headRefOid,title,author,baseRefName,state,isDraft,mergedAt,changedFiles")
            record.title = meta["title"] as? String ?? record.title
            record.author = (meta["author"] as? [String: Any])?["login"] as? String ?? ""
            record.headSHA = meta["headRefOid"] as? String ?? ""
            record.baseRef = meta["baseRefName"] as? String ?? ""
            record.prState = meta["state"] as? String ?? "OPEN"
            persist(record)

            // Diff (capped)
            let diffResult = try await ProcessRunner.run(
                ProcessSpec(executableURL: gh, arguments: ["pr", "diff", ref.url]),
                timeout: .seconds(120))
            guard diffResult.succeeded else {
                throw ReviewError.gh(diffResult.stderrText)
            }
            var diff = diffResult.stdoutText
            var truncated = false
            if diff.utf8.count > Self.maxDiffBytes {
                diff = String(diff.prefix(Self.maxDiffBytes))
                truncated = true
            }

            // Review via headless claude
            let output = try await runClaudeReview(
                claude: claude, record: record, diff: diff, truncated: truncated)

            guard let payload = FindingsPayload.extract(from: output) else {
                throw ReviewError.badModelOutput
            }
            record.summary = payload.summary
            record.findingsJSON = try JSONEncoder().encode(
                payload.findings.sorted { $0.severity < $1.severity })
            record.status = .completed
            record.completedAt = Date()
            persist(record)
        } catch {
            record.status = .failed
            record.errorMessage = "\(error)"
            persist(record)
        }
    }

    private func runClaudeReview(
        claude: URL, record: ReviewRun, diff: String, truncated: Bool
    ) async throws -> String {
        let prompt = """
        You are reviewing a GitHub pull request for correctness bugs and \
        significant issues. PR: \(record.title) by \(record.author) \
        (\(record.owner)/\(record.repo)#\(record.prNumber), base \(record.baseRef)).
        \(truncated ? "NOTE: the diff was truncated for size — say so in the summary." : "")

        Respond with ONLY a JSON object: {"summary": string, "findings": \
        [{"severity": "blocker"|"high"|"medium"|"low"|"nit", "file": string, \
        "line": integer|null, "title": string, "detail": string}]}. \
        No prose outside the JSON.

        DIFF:
        \(diff)
        """

        // Schema mode first (CLI-validated); plain JSON mode as fallback for
        // older CLIs.
        let schema = #"{"type":"object","properties":{"summary":{"type":"string"},"findings":{"type":"array","items":{"type":"object","properties":{"severity":{"type":"string","enum":["blocker","high","medium","low","nit"]},"file":{"type":"string"},"line":{"type":["integer","null"]},"title":{"type":"string"},"detail":{"type":"string"}},"required":["severity","file","title","detail"]}}},"required":["summary","findings"]}"#

        for arguments in [
            ["-p", prompt, "--output-format", "json", "--json-schema", schema,
             "--permission-mode", "dontAsk", "--allowedTools", ""],
            ["-p", prompt, "--output-format", "json",
             "--permission-mode", "dontAsk", "--allowedTools", ""],
        ] {
            let result = try await ProcessRunner.run(
                ProcessSpec(executableURL: claude, arguments: arguments),
                timeout: .seconds(600))
            if result.succeeded {
                // --output-format json wraps the reply in an envelope whose
                // `result` field is the model text (or structured output).
                if let envelope = (try? JSONSerialization.jsonObject(with: result.stdout)) as? [String: Any] {
                    if let structured = envelope["structured_output"],
                       let data = try? JSONSerialization.data(withJSONObject: structured) {
                        return String(decoding: data, as: UTF8.self)
                    }
                    if let text = envelope["result"] as? String {
                        return text
                    }
                }
                return result.stdoutText
            }
            logger.warning("claude review attempt failed: \(result.stderrText.prefix(300), privacy: .public)")
        }
        throw ReviewError.claudeFailed
    }

    // MARK: - Staleness

    func refreshStaleness() async {
        guard let gh = await sharedToolAvailability.url(for: .gh) else { return }
        for var run in runs where run.status == .completed && run.prState == "OPEN" {
            let ref = PRRef(owner: run.owner, repo: run.repo, number: run.prNumber)
            guard let meta = try? await ghJSON(gh: gh, ref: ref, fields: "headRefOid,state,mergedAt")
            else { continue }
            run.prState = meta["state"] as? String ?? run.prState
            run.lastCheckedAt = Date()
            if let head = meta["headRefOid"] as? String, head != run.headSHA, run.prState == "OPEN" {
                run.status = .stale
            }
            persist(run)
        }
    }

    // MARK: - Helpers

    private func ghJSON(gh: URL, ref: PRRef, fields: String) async throws -> [String: Any] {
        let result = try await ProcessRunner.run(
            ProcessSpec(executableURL: gh, arguments: ["pr", "view", ref.url, "--json", fields]),
            timeout: .seconds(60))
        guard result.succeeded else {
            throw ReviewError.gh(result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (try? JSONSerialization.jsonObject(with: result.stdout)) as? [String: Any] ?? [:]
    }

    private func persist(_ run: ReviewRun) {
        try? store.save(run)
        reload()
    }
}

enum ReviewError: Error, CustomStringConvertible {
    case gh(String)
    case claudeFailed
    case badModelOutput

    var description: String {
        switch self {
        case .gh(let message): "gh: \(message.prefix(200))"
        case .claudeFailed: "claude review run failed"
        case .badModelOutput: "model output was not valid findings JSON"
        }
    }
}
