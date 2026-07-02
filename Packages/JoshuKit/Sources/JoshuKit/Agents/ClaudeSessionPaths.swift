import Foundation

public enum ClaudeSessionPaths {
    /// Claude Code stores sessions under ~/.claude/projects/<slug>/ where the
    /// slug is the absolute workspace path with every `/` AND `.` replaced by
    /// `-` (verified: `/Users/x/repo/.claude/worktrees/demo` →
    /// `-Users-x-repo--claude-worktrees-demo`). Build it the same way; never
    /// reverse-engineer from directory listings.
    public static func projectSlug(for workspacePath: String) -> String {
        String(workspacePath.map { $0 == "/" || $0 == "." ? "-" : $0 })
    }

    public static func projectDirectory(
        for workspacePath: String,
        claudeHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    ) -> URL {
        claudeHome
            .appendingPathComponent("projects")
            .appendingPathComponent(projectSlug(for: workspacePath))
    }
}
