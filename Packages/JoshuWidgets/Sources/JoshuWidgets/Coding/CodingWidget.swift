import SwiftUI
import Observation
import JoshuKit

public struct CodingConfig: WidgetConfig {
    public var workspacePath: String = ""
    public init() {}
}

/// One instance per workspace: scans git worktrees, discovers Claude/Codex
/// sessions per worktree, renders them as chat-head avatars that open
/// floating chat windows.
public enum CodingWidget: WidgetDescriptor {
    public static let typeID = WidgetTypeID(rawValue: "com.wren.joshu.coding")

    public static let metadata = WidgetMetadata(
        displayName: "Coding",
        systemImage: "chevron.left.forwardslash.chevron.right",
        summary: "Worktrees and their Claude/Codex sessions as floating chat heads.",
        defaultSize: CGSize(width: 320, height: 380)
    )

    public static func makeView(model: WidgetModel<CodingConfig>) -> some View {
        CodingView(model: model)
    }
}

/// Shared across coding widget instances — probing claude/gh once is enough.
@MainActor public let sharedToolAvailability = ToolAvailability()

/// Spawn a new Claude session in a workspace (Run with Claude). Public entry
/// for the app shell; the session shows up as a coding chat-head via
/// file-driven discovery.
@MainActor
public func runWithClaude(workspacePath: String, prompt: String) {
    Task {
        try? await SpawnSessionService.startClaude(
            workspacePath: workspacePath, prompt: prompt, tools: sharedToolAvailability)
    }
}

// MARK: - Engine

@MainActor
@Observable
final class CodingEngine {
    let workspacePath: String
    private(set) var worktrees: [Worktree] = []
    private(set) var sessionsByWorktree: [String: [DiscoveredSession]] = [:]
    private(set) var errorText: String?
    private(set) var isRefreshing = false

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var livenessTimer: Task<Void, Never>?

    init(workspacePath: String) {
        self.workspacePath = workspacePath
        Task { await refresh() }
        // Liveness decays with wall-clock time even with no file events.
        livenessTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.refresh()
            }
        }
    }

    deinit {
        watcher?.stop()
        livenessTimer?.cancel()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let git = await sharedToolAvailability.url(for: .git) else {
            errorText = "git not found"
            return
        }

        do {
            let trees = try await CodingServices.listWorktrees(repoPath: workspacePath, git: git)
            worktrees = trees.filter { !$0.prunable }
            var discovered: [String: [DiscoveredSession]] = [:]
            for tree in worktrees {
                let claude = CodingServices.discoverClaudeSessions(worktreePath: tree.path)
                let codex = CodingServices.discoverCodexSessions(worktreePath: tree.path)
                discovered[tree.path] = (claude + codex).sorted { $0.lastActivity > $1.lastActivity }
            }
            sessionsByWorktree = discovered
            errorText = nil
            startWatching()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func startWatching() {
        guard watcher == nil else { return }
        var paths = worktrees.map { ClaudeSessionPaths.projectDirectory(for: $0.path) }
        paths.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions"))
        let watcher = FileWatcher(paths: paths, latency: 1.0)
        self.watcher = watcher
        watchTask = Task { [weak self] in
            for await _ in watcher.events {
                await self?.refresh()
            }
        }
    }
}

// MARK: - Views

private struct CodingView: View {
    @Bindable var model: WidgetModel<CodingConfig>

    var body: some View {
        if model.config.workspacePath.isEmpty {
            WorkspaceSetupView(model: model)
        } else {
            WorkspaceView(model: model)
                .id(model.config.workspacePath) // rebuild engine on repoint
        }
    }
}

private struct WorkspaceSetupView: View {
    @Bindable var model: WidgetModel<CodingConfig>
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Coding", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            Text("Point this widget at a repository. Worktrees and their Claude/Codex sessions appear as chat heads.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            TextField("/path/to/repo", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(apply)

            Button("Set Workspace", action: apply)
                .disabled(draft.isEmpty)

            Spacer()
        }
        .padding(16)
    }

    private func apply() {
        let expanded = NSString(string: draft).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return }
        model.config.workspacePath = expanded
    }
}

private struct WorkspaceView: View {
    let model: WidgetModel<CodingConfig>
    @State private var engine: CodingEngine

    init(model: WidgetModel<CodingConfig>) {
        self.model = model
        _engine = State(initialValue: CodingEngine(workspacePath: model.config.workspacePath))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    URL(fileURLWithPath: engine.workspacePath).lastPathComponent,
                    systemImage: "folder")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button {
                    Task { await engine.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            if let errorText = engine.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(engine.worktrees) { worktree in
                        WorktreeRow(
                            worktree: worktree,
                            sessions: engine.sessionsByWorktree[worktree.path] ?? [],
                            model: model)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }
}

private struct WorktreeRow: View {
    let worktree: Worktree
    let sessions: [DiscoveredSession]
    let model: WidgetModel<CodingConfig>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                Text(worktree.displayName)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.75))

            if sessions.isEmpty {
                Text("No sessions")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                HStack(spacing: -8) { // overlapping avatar stack
                    ForEach(sessions.prefix(8)) { session in
                        SessionAvatar(session: session) {
                            openChat(session)
                        }
                    }
                    if sessions.count > 8 {
                        Text("+\(sessions.count - 8)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func openChat(_ session: DiscoveredSession) {
        model.shell.presentAuxiliaryWindow(
            key: "chat-\(session.id)",
            options: AuxiliaryWindowOptions(
                size: CGSize(width: 380, height: 480),
                attachment: .anchored(edge: .trailing, gap: 12))
        ) {
            ChatWindowView(session: session)
        }
    }
}

struct SessionAvatar: View {
    let session: DiscoveredSession
    var action: () -> Void

    @State private var pulsing = false

    private var color: Color {
        session.tool == .claude
            ? Color(hue: 0.06, saturation: 0.7, brightness: 0.9)   // claude coral
            : Color(hue: 0.58, saturation: 0.6, brightness: 0.85)  // codex blue
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.gradient)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(session.tool == .claude ? "C" : "X")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                .overlay {
                    if session.liveness == .live {
                        Circle()
                            .strokeBorder(.green.opacity(pulsing ? 0.15 : 0.9), lineWidth: 2)
                            .scaleEffect(pulsing ? 1.25 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                value: pulsing)
                            .onAppear { pulsing = true }
                    }
                }
        }
        .buttonStyle(.plain)
        .help("\(session.title) — \(session.liveness == .live ? "recently active" : "historical")")
    }
}
