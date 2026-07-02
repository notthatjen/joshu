import Foundation
import Observation
import JoshuKit
import os

/// State behind one chat window: full transcript load, live tail of the
/// session file, and continue-conversation via headless `claude`.
@MainActor
@Observable
final class ChatEngine {
    private(set) var session: DiscoveredSession
    private(set) var messages: [TranscriptMessage] = []
    private(set) var driftCount = 0
    private(set) var isSending = false
    private(set) var statusText: String?
    private(set) var forkedFromID: String?

    @ObservationIgnored private var seenMessageIDs: Set<String> = []
    @ObservationIgnored private var tailOffset: UInt64 = 0
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private let tools: ToolAvailability
    @ObservationIgnored private let parser = ClaudeTranscriptParser()
    @ObservationIgnored private let codexParser = CodexTranscriptParser()
    @ObservationIgnored private let logger = Logger(subsystem: "com.wren.joshu", category: "ChatEngine")

    var canSend: Bool { session.tool == .claude && !isSending }

    init(session: DiscoveredSession, tools: ToolAvailability) {
        self.session = session
        self.tools = tools
        loadFull()
        startTail()
    }

    deinit {
        watcher?.stop()
    }

    // MARK: - Transcript

    private func loadFull() {
        guard let data = try? Data(contentsOf: session.fileURL) else { return }
        var parsed = ParsedSession()
        switch session.tool {
        case .claude: parsed = parser.parse(data: data)
        case .codex: parsed = codexParser.parse(data: data)
        }
        driftCount = parsed.unknownRecords
        messages = parsed.messages
        seenMessageIDs = Set(parsed.messages.map(\.id))
        tailOffset = UInt64(data.count)
    }

    private func startTail() {
        watcher?.stop()
        let watcher = FileWatcher(paths: [session.fileURL.deletingLastPathComponent()], latency: 0.25)
        self.watcher = watcher
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            for await changed in watcher.events {
                guard let self else { return }
                guard changed.contains(where: { $0.path == self.session.fileURL.path }) else { continue }
                self.consumeTail()
            }
        }
    }

    private func consumeTail() {
        guard let (lines, newOffset) = try? TranscriptTail.readNewLines(
            fileURL: session.fileURL, from: tailOffset) else { return }
        tailOffset = newOffset
        appendParsed(lines: lines)
    }

    private func appendParsed(lines: [String]) {
        guard !lines.isEmpty else { return }
        var scratch = ParsedSession()
        for line in lines {
            switch session.tool {
            case .claude: parser.parseLine(line, into: &scratch)
            case .codex: codexParser.parseLine(line, into: &scratch)
            }
        }
        driftCount += scratch.unknownRecords
        appendMessages(scratch.messages)
    }

    /// Stream events and file tail both land here; ids match (Claude reuses
    /// the record uuid in stream-json), so duplicates drop out naturally.
    private func appendMessages(_ new: [TranscriptMessage]) {
        for message in new where !seenMessageIDs.contains(message.id) {
            seenMessageIDs.insert(message.id)
            messages.append(message)
        }
    }

    // MARK: - Continue conversation (Claude MVP)

    func send(_ text: String) {
        guard canSend, !text.isEmpty else { return }
        isSending = true
        statusText = nil

        sendTask = Task { [weak self] in
            await self?.performSend(text)
        }
    }

    func cancelSend() {
        sendTask?.cancel()
        isSending = false
        statusText = "Cancelled"
    }

    private func performSend(_ text: String) async {
        defer { isSending = false }

        guard let claudeURL = await tools.url(for: .claude) else {
            statusText = "claude CLI not found — install it or check PATH"
            return
        }

        // Never in-place-resume a session another live process owns — that
        // interleaves writes into its JSONL. Fork instead.
        let shouldFork = CodingServices.livenessByRecency(session.lastActivity) == .live

        var arguments = [
            "--resume", session.id,
            "-p", text,
            "--output-format", "stream-json",
            "--verbose", // mandatory with -p + stream-json
            "--permission-mode", "dontAsk",
            "--allowedTools", "Read,Grep,Glob",
        ]
        if shouldFork {
            arguments.append("--fork-session")
            statusText = "Session looks active elsewhere — forking…"
        }

        // Echo the user turn immediately; the stream/file will confirm it.
        appendMessages([TranscriptMessage(
            id: "local-\(UUID().uuidString)", role: .user,
            blocks: [.text(text)], timestamp: Date())])

        let spec = ProcessSpec(
            executableURL: claudeURL,
            arguments: arguments,
            workingDirectory: URL(fileURLWithPath: session.cwd))

        do {
            for try await event in ProcessRunner.streamLines(spec) {
                guard !Task.isCancelled else { return }
                switch event {
                case .stdoutLine(let line):
                    handleStreamLine(line, didFork: shouldFork)
                case .stderrLine(let line):
                    logger.warning("claude stderr: \(line, privacy: .public)")
                case .exit(let code):
                    if code != 0 {
                        statusText = "claude exited with code \(code)"
                    } else if statusText?.hasPrefix("Session looks active") == true {
                        // keep the fork banner
                    } else {
                        statusText = nil
                    }
                }
            }
        } catch {
            statusText = "send failed: \(error.localizedDescription)"
        }
    }

    private func handleStreamLine(_ line: String, didFork: Bool) {
        guard
            let record = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        else { return }

        // Fork re-bind: the init event carries the (possibly new) session id.
        if record["type"] as? String == "system",
           let newID = record["session_id"] as? String, newID != session.id {
            rebind(to: newID, forkedFrom: didFork ? session.id : nil)
        }

        // stream-json events mirror session records — reuse the parser.
        var scratch = ParsedSession()
        parser.parseLine(line, into: &scratch)
        appendMessages(scratch.messages)
    }

    private func rebind(to newID: String, forkedFrom: String?) {
        let newURL = session.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(newID).jsonl")
        forkedFromID = forkedFrom
        session = DiscoveredSession(
            id: newID, tool: session.tool,
            title: session.title, fileURL: newURL,
            cwd: session.cwd, lastActivity: Date(), liveness: .live)
        tailOffset = 0
        startTail()
        if forkedFrom != nil {
            statusText = "Forked — continuing in a new session"
        }
    }
}
