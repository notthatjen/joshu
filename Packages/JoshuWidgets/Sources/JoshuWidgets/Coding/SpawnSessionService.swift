import Foundation
import JoshuKit

/// Starts brand-new Claude sessions in a chosen worktree. Shared by the
/// coding widget (new-session button) and the meeting widget (Run with
/// Claude). The pre-generated `--session-id` means the caller knows the
/// session file to watch immediately instead of racing discovery, and the
/// new session shows up as a chat-head automatically (discovery is
/// file-driven).
public enum SpawnSessionService {
    public struct Spawned: Sendable {
        public let sessionID: String
        public let workspacePath: String
    }

    /// Fire-and-forget: launch a headless claude turn seeded with `prompt`.
    /// Returns the session id the transcript will be written under. The
    /// caller doesn't await completion — the coding widget will surface the
    /// session as it writes to disk.
    @discardableResult
    public static func startClaude(
        workspacePath: String,
        prompt: String,
        tools: ToolAvailability
    ) async throws -> Spawned {
        guard let claude = await tools.url(for: .claude) else {
            throw CodingError.toolMissing("claude")
        }
        let sessionID = UUID().uuidString

        let spec = ProcessSpec(
            executableURL: claude,
            arguments: [
                "-p", prompt,
                "--session-id", sessionID,
                "--output-format", "stream-json",
                "--verbose",
                "--permission-mode", "dontAsk",
                "--allowedTools", "Read,Grep,Glob",
            ],
            workingDirectory: URL(fileURLWithPath: workspacePath))

        // Drain in the background so the child isn't blocked on a full pipe;
        // the widget observes progress via the session file, not this stream.
        Task.detached {
            for try await _ in ProcessRunner.streamLines(spec) {}
        }

        return Spawned(sessionID: sessionID, workspacePath: workspacePath)
    }
}
