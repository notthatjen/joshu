import Foundation
import os

public enum Tool: String, CaseIterable, Sendable {
    case claude, codex, gh, git
}

public enum ToolStatus: Sendable {
    case ok(version: String, url: URL)
    case missing
    case unauthenticated(URL)
    case error(String)

    public var isUsable: Bool {
        if case .ok = self { return true }
        return false
    }
}

/// Probes which CLIs exist and whether they're authenticated, resolving each
/// through the user's *login shell* PATH — a GUI app launched from Finder
/// gets a minimal PATH that misses /opt/homebrew/bin etc., so bare tool
/// names would silently "not exist".
public actor ToolAvailability {
    private var statuses: [Tool: ToolStatus] = [:]
    private var loginPATH: String?
    private let logger = Logger(subsystem: "com.wren.joshu", category: "ToolAvailability")

    public init() {}

    public func status(for tool: Tool) async -> ToolStatus {
        if let cached = statuses[tool] { return cached }
        let status = await probe(tool)
        statuses[tool] = status
        return status
    }

    public func url(for tool: Tool) async -> URL? {
        switch await status(for: tool) {
        case .ok(_, let url): return url
        case .unauthenticated(let url): return url
        case .missing, .error: return nil
        }
    }

    /// Version string captured at probe time — feeds schema-drift telemetry.
    public func version(of tool: Tool) async -> String? {
        if case .ok(let version, _) = await status(for: tool) { return version }
        return nil
    }

    public func refresh() async {
        statuses.removeAll()
        loginPATH = nil
        for tool in Tool.allCases {
            _ = await status(for: tool)
        }
    }

    // MARK: - Probing

    private func probe(_ tool: Tool) async -> ToolStatus {
        guard let url = await resolveExecutable(tool.rawValue) else { return .missing }

        switch tool {
        case .gh:
            // `gh auth status` distinguishes installed-but-logged-out.
            let auth = try? await ProcessRunner.run(
                ProcessSpec(executableURL: url, arguments: ["auth", "status"]),
                timeout: .seconds(15))
            if let auth, !auth.succeeded {
                return .unauthenticated(url)
            }
            return await versionStatus(url, arguments: ["--version"])
        case .claude:
            return await versionStatus(url, arguments: ["--version"])
        case .codex:
            return await versionStatus(url, arguments: ["--version"])
        case .git:
            return await versionStatus(url, arguments: ["--version"])
        }
    }

    private func versionStatus(_ url: URL, arguments: [String]) async -> ToolStatus {
        do {
            let result = try await ProcessRunner.run(
                ProcessSpec(executableURL: url, arguments: arguments), timeout: .seconds(15))
            guard result.succeeded else {
                return .error(result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let version = result.stdoutText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? "?"
            return .ok(version: version, url: url)
        } catch {
            return .error("\(error)")
        }
    }

    private func resolveExecutable(_ name: String) async -> URL? {
        let path = await resolveLoginPATH()
        for directory in path.components(separatedBy: ":") where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func resolveLoginPATH() async -> String {
        if let loginPATH { return loginPATH }
        // Marker line survives any rc-file noise an interactive shell prints.
        let spec = ProcessSpec(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-l", "-i", "-c", #"printf '__JOSHU_PATH__%s\n' "$PATH""#])
        let fallback = ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"

        let resolved: String
        if let result = try? await ProcessRunner.run(spec, timeout: .seconds(10)),
           let line = result.stdoutText
                .components(separatedBy: .newlines)
                .last(where: { $0.hasPrefix("__JOSHU_PATH__") }) {
            resolved = String(line.dropFirst("__JOSHU_PATH__".count)) + ":" + fallback
        } else {
            logger.warning("login-shell PATH resolution failed; using inherited PATH")
            resolved = fallback + ":/opt/homebrew/bin:/usr/local/bin"
        }
        loginPATH = resolved
        return resolved
    }
}
