# Joshu — macOS Overlay Assistant-Widget App

## Context

Greenfield app (repo `/Users/jencarlovillaganas/work/wren/joshu-assistant` is empty, git initialized). Jen wants a Mac app that overlays floating, always-on-top, interactive glass widgets (visionOS/Liquid-Glass aesthetic per the reference screenshot) hosting AI assistants:

- **Coding widget** — one instance per workspace; scans git worktrees; discovers existing Claude Code / Codex sessions per worktree; sessions render as stacked chat-head avatars (à la old Facebook Messenger); clicking opens a floating chat window with transcript + continue-conversation.
- **Reviewer widget** — paste PR URL → AI review; history list; staleness detection (new commits since review) with re-run.
- **Meeting widget** — Granola integration; detect meeting end, pull transcript, extract action items; immediate items pop as edge toasts with auto-hide timer and CTA dropdown (Copy prompt / Run with Claude → workspace picker).

Should eventually port to visionOS → keep portable code AppKit-free.

**Decisions confirmed with user:** native SwiftUI + AppKit (NSPanel), menu-bar app, macOS 14+ target; build order Shell → Coding → Reviewer → Meeting; Granola via HTTP API (local cache is now encrypted — verified `cache-v6.json.enc` + Keychain "Granola Safe Storage"; old plaintext `cache-v3.json` no longer exists).

**Environment verified:** Xcode 26.6 on macOS 26.5, `xcodegen` installed, `gh` at `/opt/homebrew/bin/gh`, `~/.codex/auth.json` present, real Claude/Codex session files inspected for schemas.

## Architecture

### Build system & layout

XcodeGen (`project.yml` source of truth, generated `.xcodeproj` gitignored) + local SwiftPM packages. Non-sandboxed (reads `~/.claude`, `~/.codex`, spawns CLIs); Developer ID distribution, not MAS.

```
joshu-assistant/
├── project.yml                  # XcodeGen manifest
├── Makefile                     # gen / build / test / run
├── Joshu/                       # app target — ONLY AppKit-touching code
│   ├── App/        JoshuApp.swift (@main, MenuBarExtra), AppDelegate, AppEnvironment (composition root)
│   ├── Windows/    FloatingPanel.swift, PanelController, PanelManager, AuxiliaryPanelController,
│   │               PanelPlacementResolver, SnapEngine
│   ├── MenuBar/    MenuBarView, GalleryWindowController
│   ├── Hotkey/     HotkeyManager (sindresorhus/KeyboardShortcuts, default ⌥Space)
│   └── Shell/      MacWidgetShellContext.swift
├── Packages/
│   ├── JoshuKit/                # platform-agnostic: Widget protocol, Store, Registry, DesignSystem,
│   │                            # Core services (ProcessRunner, ToolAvailability, FileWatcher)
│   └── JoshuWidgets/            # Coding/, Reviewer/, Meeting/, BuiltinWidgets.all
└── Tests/                       # JoshuKitTests (SPM), JoshuAppTests
```

### Window management

One `NSPanel` per widget instance (not a canvas window — avoids click-through hacks, gives native drag/key/multi-display).

`FloatingPanel` config: `styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isMovableByWindowBackground = true`, `becomesKeyOnlyIfNeeded = true`, `isReleasedWhenClosed = false`, `hasShadow = false` (shadow drawn in SwiftUI).

**Known gotchas to handle:**
- `override var canBecomeKey: Bool { true }` — mandatory or text fields never focus in borderless panels.
- LSUIElement app has no menu bar → install programmatic hidden Edit menu (`cut:/copy:/paste:/selectAll:/undo:`) or ⌘C/⌘V dead in text fields.
- Positions stored as `PanelPlacement { screenUUID, originFraction (0–1 of visibleFrame), size }` — survives resolution changes; clamp into `visibleFrame` on restore; re-clamp on `didChangeScreenParametersNotification`.
- `SnapEngine`: pure function snapping to screen/panel edges, threshold 12pt — unit-testable.

### Widget plugin system (JoshuKit)

- `WidgetDescriptor` protocol: `typeID`, `metadata` (name, icon, defaultSize, allowsMultipleInstances), associated `Config: Codable`, `makeView(model:)`, optional `makeService(model:)` (background `WidgetService` with `start()/stop()`).
- `AnyWidgetDescriptor` type erasure; `WidgetRegistry` = `[WidgetTypeID: AnyWidgetDescriptor]` populated from `BuiltinWidgets.all`.
- `WidgetModel<Config>` (@Observable) — per-instance live object; config mutations flow to store via `WidgetShellContext.configDidChange`.
- Unknown typeID on load → keep record, show "missing widget type" placeholder.
- Services keep running when widgets hidden; stop only on removal/quit.

### Persistence

JSON file `~/Library/Application Support/Joshu/widgets.json` (`schemaVersion` + `[WidgetInstanceRecord{id, typeID, configJSON, placement, zIndex}]`), atomic writes, debounced ~500ms, corrupted → `.bak` + fresh. (Not SwiftData — payload tiny, config heterogeneous, keeps JoshuKit dependency-free.) Reviewer/Meeting widgets get a GRDB SQLite DB for review history / processed meetings.

### Secondary windows (chat heads → chat)

`WidgetShellContext.presentAuxiliaryWindow(key:options:content:)` — shell creates another `FloatingPanel`; `.anchored` uses `addChildWindow` so chat rides along with the avatar stack; same `key` → bring to front, not duplicate. Not persisted by shell. Maps to `openWindow` on visionOS.

### Glass aesthetic

Critical: SwiftUI `.ultraThinMaterial` blends within-window — looks flat on a transparent panel. Use `NSVisualEffectView(blendingMode: .behindWindow, material: .hudWindow, state: .active)` with layer cornerRadius 24 (clipShape doesn't clip behind-window blur). Stack: blur → black 0.25 tint → content → top-lit rim gradient stroke (white 0.4→0.06, 1pt) → SwiftUI shadow (needs ~30pt transparent panel inset since hasShadow=false). `if #available(macOS 26)` use `.glassEffect(...)`. Respect reduce-transparency → solid fill.

## Integrations (verified on this machine)

### Shared foundation (build first)

- **`ProcessRunner`** (actor): one-shot + streaming (`AsyncThrowingStream` of stdout lines). Drain stdout/stderr concurrently (pipe deadlock). **PATH gotcha:** GUI apps don't get Homebrew PATH — resolve absolute tool paths once via login shell (`/bin/zsh -lic 'echo $PATH'` + `which`), never invoke bare `claude`.
- **`ToolAvailability`** (actor): probe claude/codex/gh/git → `.ok/.missing/.unauthenticated`; gates CTAs with "install X / login" states.
- **`FileWatcher`**: FSEvents wrapper → debounced `AsyncStream<Set<URL>>` of changed paths. FSEvents tells *that* something changed; cheap stat/tail tells *what*.

### Coding widget

- Worktrees: `git worktree list --porcelain` → `[Worktree{path, branch, head, prunable}]`.
- **Claude discovery:** slug = worktree path with every `/` AND `.` → `-` (verified: `/.` becomes `--`); scan `~/.claude/projects/<slug>/*.jsonl`. Title from the `ai-title` record. Render `user`/`assistant` records; assistant content = array of `{thinking|text|tool_use|tool_result}`; order by timestamp, skip `isSidechain: true`.
- **Codex discovery:** `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`; line 1 = `session_meta` with `payload.cwd` — filter by cwd == worktree path. Fast-list via `~/.codex/session_index.jsonl` (no cwd there — confirm from rollout line 1, cache id→cwd).
- Normalize both into `TranscriptMessage{role, blocks, timestamp}` via `TranscriptParser` protocol (Claude + Codex impls) with **incremental tail-parse** (byte offset, partial-line buffer — never re-parse whole file).
- **Liveness** (`historical | liveIdle | liveBusy | unknown`): primary = JSONL appended within ~30–60s; Codex authoritative via `~/.codex/process_manager/chat_processes.json`; Claude confirm via process scan + cwd. No lock files exist — heuristic only. Live avatar = pulsing ring.
- **Continue conversation (MVP):** headless per-message `claude --resume <id> -p "<msg>" --output-format stream-json` (flags verified). **Never in-place-resume a session owned by another live process** (JSONL corruption) — offer `--fork-session` (verified flag) or read-only tail. Codex later: `codex exec resume <id> --json`. Embedded terminal (SwiftTerm) = later power-mode; Agent SDK sidecar = only if CLI proves limiting.
- `SpawnSessionService.startClaude(in: worktree, prompt:)` — new sessions; shared with meeting widget; new sessions appear as chat-heads automatically (discovery is file-driven).
- One `AgentSessionDriver` protocol (loadTranscript / follow / sendMessage) so chat window is tool-agnostic.

### Reviewer widget

- Flow: parse URL → `gh pr view --json headRefOid,title,author,baseRefName,state` + `gh pr diff` → `claude -p` with versioned review-prompt template instructing JSON-only findings output → parse (fenced-block extraction + one repair retry) → persist.
- Model: `ReviewSubject{owner,repo,prNumber}` parent + `ReviewRun{headSHA, status, findings[], promptVersion, timestamps}` children — history = runs list.
- Staleness: stored headSHA vs `gh pr view --json headRefOid`; check on widget focus + every 5 min while visible; never poll closed/merged.
- Bounded queue (max 2–3 concurrent claude runs), cancellable; re-run cancels in-flight.
- Edge cases: gh missing/unauthed CTAs, non-PR URLs, huge diffs (MVP: cap + warn), fork PRs.

### Meeting widget (Granola — Path A: HTTP API)

- **Local cache is encrypted** (verified): `cache-v6.json.enc`, `granola.db` (encrypted blob), `storage.dek` wrapped by Keychain item "Granola Safe Storage". Do NOT build on plaintext cache.
- MVP path: read WorkOS `access_token` from Granola local state (Keychain-decrypt where needed), call Granola documents/transcripts endpoints; refresh via refresh_token; on failure CTA "open Granola / sign in". Endpoints are undocumented — first implementation task is confirming them; local-decrypt (Path C) stays documented as fallback.
- Poll 30–60s for completed docs (end time + transcript ready, id not in `ProcessedMeetings` dedupe table).
- Extract via `claude -p --output-format json` → `[ActionItem{text, owner?, isImmediate, suggestedPrompt}]`.
- Immediate items → edge toast (non-activating panel, auto-hide ~12s, hover-to-persist, stack): Copy prompt (NSPasteboard) / Run with Claude → worktree picker → `SpawnSessionService`.
- Privacy: transcripts local-only, never logged, purgeable.

### Future widget ideas (documented, not built)

Agent Fleet Monitor (all live sessions across repos), Next-Meeting HUD, Prompt Library, CI/PR status strip ("have Claude investigate failure"), Inbox Triage, Worktree Launcher.

## Milestones

- **M0 — floats**: project.yml, Makefile, packages skeleton, LSUIElement + MenuBarExtra, FloatingPanel + one hard-coded glass panel, drag, ⌥Space toggle, hidden Edit menu. *Exit: `make build` green; panel floats over fullscreen Safari; text field types without activating app; position restores.*
- **M1 — plugin system**: WidgetDescriptor/Registry/Store, PanelManager reconciliation, gallery "+" flow, multi-instance, remove, JSON round-trip + unknown-type placeholder. *Exit: add 3 dummies, relaunch, all restore.*
- **M2 — placement polish**: screen-UUID placement, SnapEngine, screen-change clamp, cascade.
- **M3 — aux windows**: presentAuxiliaryWindow, child-window anchoring, chat-heads demo.
- **M4 — glass & motion**: full glass stack, macOS 26 branch, reduce-transparency, hover chrome, show/hide animation.
- **M5 — foundation services**: ProcessRunner (+PATH resolution), ToolAvailability, FileWatcher, GRDB store, Settings (hotkey recorder, launch-at-login via SMAppService).
- **M6 — Coding widget MVP**: worktree scan, Claude+Codex discovery, transcript render (read-only + live tail), liveness heuristic, avatars, continue-via-headless-claude (fork if live).
- **M7 — Reviewer widget MVP**: URL → review → findings by severity → re-run + staleness on focus.
- **M8 — Meeting widget MVP**: Granola API source, poll, extract, toasts, Run-with-Claude spawn.

## Verification

- `make gen && make build` (xcodebuild) green at every milestone; `make test` = xcodebuild test + `swift test` in JoshuKit.
- Unit tests: store round-trip/corruption/unknown-type, SnapEngine math, PanelPlacement fraction↔frame + clamping, transcript parsers against fixture JSONL copied from real `~/.claude`/`~/.codex` sessions (sanitized), slug builder, review JSON parse+repair.
- Manual smoke checklist (`docs/SMOKE.md`): menu-bar-only launch, gallery add, drag to 2nd monitor, hotkey hide/show, type while Finder frontmost, ⌘C/⌘V, overlay over fullscreen app, relaunch restore, display-unplug clamp. (XCUITest useless for nonactivating borderless panels.)
- Integration smoke: coding widget against this machine's real sessions; reviewer against a real PR URL; `log stream --predicate 'subsystem == "com.wren.joshu"'` for CLI-visible logging.

## Notes for implementation

- Per superpowers flow: on approval, first write this design as spec to `docs/superpowers/specs/2026-07-02-joshu-overlay-widgets-design.md`, commit, then implement milestone-by-milestone with TDD where testable (parsers, store, snap math).
- Dependencies: KeyboardShortcuts (SPM), GRDB (SPM, from M5). Nothing else.
