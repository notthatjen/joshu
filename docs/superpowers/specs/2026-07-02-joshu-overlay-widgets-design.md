
# Joshu — macOS Overlay Assistant-Widget App

## Context

Greenfield app (repo `/Users/jencarlovillaganas/work/wren/joshu-assistant` is empty, git initialized). Jen wants a Mac app that overlays floating, always-on-top, interactive glass widgets (visionOS/Liquid-Glass aesthetic per the reference screenshot) hosting AI assistants:

- **Coding widget** — one instance per workspace; scans git worktrees; discovers existing Claude Code / Codex sessions per worktree; sessions render as stacked chat-head avatars (à la old Facebook Messenger); clicking opens a floating chat window with transcript + continue-conversation.
- **Reviewer widget** — paste PR URL → AI review; history list; staleness detection (new commits since review) with re-run.
- **Meeting widget** — Granola integration; detect meeting end, pull transcript, extract action items; immediate items pop as edge toasts with auto-hide timer and CTA dropdown (Copy prompt / Run with Claude → workspace picker).

Should eventually port to visionOS → keep portable code AppKit-free.

**Decisions confirmed with user:** native SwiftUI + AppKit (NSPanel), menu-bar app, macOS 14+ target; build order Shell → Coding → Reviewer → Meeting; Granola via HTTP API (local cache is now encrypted — verified `cache-v6.json.enc` + Keychain "Granola Safe Storage"; old plaintext `cache-v3.json` no longer exists).

**Environment verified:** Xcode 26.6 on macOS 26.5, `xcodegen` installed, `gh` at `/opt/homebrew/bin/gh`, `~/.codex/auth.json` present, real Claude/Codex session files inspected for schemas.

**CLI/API assumptions re-verified (2026-07-02, on this machine):**
- `claude --help`: `--resume <id>`, `--fork-session`, `--input-format stream-json`, `--output-format stream-json`, `--include-partial-messages`, `--session-id <uuid>`, `--json-schema <schema>`, `--max-budget-usd` all present. **Gotcha (verified by running it):** `claude -p … --output-format stream-json` errors with `When using --print, --output-format=stream-json requires --verbose` — always pass `--verbose`.
- **`--permission-prompt-tool` no longer exists.** Headless permission control is now `--permission-mode` (`default | acceptEdits | dontAsk | auto | bypassPermissions | plan`) plus `--allowedTools` / `--disallowedTools` / `--tools`. In `-p` mode there is no interactive prompt; anything that would prompt is denied. Plan for explicit permission policy (see Coding widget).
- `codex exec resume [SESSION_ID] [PROMPT] --json` verified (JSONL events on stdout); also `-o/--output-last-message <file>` and `--output-schema <file>`. `codex exec resume` filters sessions by cwd by default (`--all` disables) — consistent with our per-worktree model.
- `gh pr view --json`: `headRefOid,title,author,baseRefName,state` all valid; also available and useful: `isDraft, mergedAt, reviewDecision, statusCheckRollup, isCrossRepository, changedFiles, additions, deletions`.
- `~/.codex/process_manager/chat_processes.json` and `~/.codex/session_index.jsonl` (`{id, thread_name, updated_at}` — no cwd) confirmed present.
- **Granola now has an official API** (docs.granola.ai): `grn_…` API keys, list-notes + note-with-transcript endpoints, rate limit 5 req/s sustained / 25 per 5 s burst — but API-key creation is **Business plan and above**. Reverse-engineered path (`POST api.granola.ai/v2/get-documents`, `POST /v1/get-document-transcript`, WorkOS token with refresh rotation) remains documented in the community. Which path applies to Jen's account is unknown → dedicated spike milestone (M8a).

**Key risks tracked in this plan:**
1. Nonactivating borderless NSPanel focus/key handling (text input, ⌘C/⌘V with app never active) — M0 exit criteria cover it.
2. `stream-json` schema drift across Claude Code / Codex releases (both are fast-moving, formats unversioned) — tolerant parsing + fixture contract tests in M6.
3. Headless permission prompts (no TTY → silent denials) — explicit permission policy + denial surfacing in M6.
4. Granola API access uncertainty (plan tier, undocumented fallback endpoints, token extraction from encrypted storage) — isolated in spike M8a so M8b builds on a proven source.
5. Behind-window blur clipping — use `maskImage`, not `layer.cornerRadius` (see Glass aesthetic).

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
├── Scripts/                     # granola-spike + fixture-refresh tooling
└── Tests/                       # JoshuKitTests (SPM), JoshuAppTests
```

### Window management

One `NSPanel` per widget instance (not a canvas window — avoids click-through hacks, gives native drag/key/multi-display). Architecture question revisited: no concrete flaw found; expected panel count is O(10), well under any window-server concern, and per-panel key handling is exactly what chat input needs. **Decision stands.**

`FloatingPanel` config: `styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isMovableByWindowBackground = true`, `becomesKeyOnlyIfNeeded = true`, `isReleasedWhenClosed = false`, `hasShadow = false` (shadow drawn in SwiftUI).

**Known gotchas to handle (all exercised by M0 exit criteria):**
- `override var canBecomeKey: Bool { true }` — mandatory or text fields never focus in borderless panels.
- **The app never activates** (that's the point of `.nonactivatingPanel`), so main-menu key equivalents don't fire even with a menu installed. Two layers of defense: (a) programmatic hidden Edit menu (`cut:/copy:/paste:/selectAll:/undo:/redo:`) for the rare activated case (gallery/settings windows), and (b) `override performKeyEquivalent(with:)` on `FloatingPanel` that maps ⌘X/⌘C/⌘V/⌘A/⌘Z/⇧⌘Z to `NSApp.sendAction(_:to:from:)` on the first responder. Smoke-test both while Finder is frontmost.
- SwiftUI `@FocusState` is unreliable in borderless panels — set the panel's `initialFirstResponder` / call `makeFirstResponder` from the hosting controller when the panel becomes key.
- `hasShadow = false` + ~30pt transparent inset for the SwiftUI shadow means the panel's frame is larger than its visible glass. Override `NSView.hitTest` (or use a custom content view) so clicks and `isMovableByWindowBackground` drags in the transparent margin pass through; otherwise widgets steal clicks around their visible edges.
- Positions stored as `PanelPlacement { screenUUID, originFraction (0–1 of visibleFrame), size }` — survives resolution changes; clamp into `visibleFrame` on restore; re-clamp on `didChangeScreenParametersNotification`.
- `SnapEngine`: pure function snapping to screen/panel edges, threshold 12pt — unit-testable.

### Widget plugin system (JoshuKit)

- `WidgetDescriptor` protocol: `typeID`, `metadata` (name, icon, defaultSize, allowsMultipleInstances), associated `Config: Codable`, `makeView(model:)`, optional `makeService(model:)` (background `WidgetService` with `start()/stop()`).
- `AnyWidgetDescriptor` type erasure; `WidgetRegistry` = `[WidgetTypeID: AnyWidgetDescriptor]` populated from `BuiltinWidgets.all`. Architecture question revisited: type erasure is the standard cost of heterogeneous `Config` types and the registry is tiny; the alternative (enum of widget kinds) blocks the plugin/future-widget story. **Decision stands** — but keep `AnyWidgetDescriptor` a thin box (erased view factory + service factory + config codec), nothing else, so the erasure surface stays testable.
- `WidgetModel<Config>` (@Observable) — per-instance live object; config mutations flow to store via `WidgetShellContext.configDidChange`.
- Unknown typeID on load → keep record, show "missing widget type" placeholder.
- Services keep running when widgets hidden; stop only on removal/quit.

### Persistence

JSON file `~/Library/Application Support/Joshu/widgets.json` (`schemaVersion` + `[WidgetInstanceRecord{id, typeID, configJSON, placement, zIndex}]`), atomic writes, debounced ~500ms, corrupted → `.bak` + fresh. Architecture question revisited: payload is a handful of records written on drag/config change; SwiftData/GRDB would add a dependency and migration machinery for zero benefit, and JSON keeps JoshuKit dependency-free for visionOS. **Decision stands.** Reviewer/Meeting widgets get a GRDB SQLite DB (GRDB 7.x, verified Swift 6.1+/Xcode 16.3+ — fine here) for review history / processed meetings — introduced in M7 where it's first used, not before.

### Secondary windows (chat heads → chat)

`WidgetShellContext.presentAuxiliaryWindow(key:options:content:)` — shell creates another `FloatingPanel`; `.anchored` uses `addChildWindow` so chat rides along with the avatar stack; same `key` → bring to front, not duplicate. Not persisted by shell. Maps to `openWindow` on visionOS. Gotcha: child windows of a `.canJoinAllSpaces` panel — verify Space-switch behavior in M3 (child must follow parent; if not, fall back to manual frame-following on parent `didMove`).

### Glass aesthetic

Critical: SwiftUI `.ultraThinMaterial` blends within-window — looks flat on a transparent panel. Use `NSVisualEffectView(blendingMode: .behindWindow, material: .hudWindow, state: .active)`. **Corner rounding (corrected):** `layer.cornerRadius`/`clipShape` do not reliably clip behind-window blur — set the effect view's **`maskImage`** (resizable `NSImage` rounded-rect with cap insets, radius 24); when the effect view is the window's content view the mask is forwarded to the window server. Stack: blur → black 0.25 tint → content → top-lit rim gradient stroke (white 0.4→0.06, 1pt) → SwiftUI shadow (needs ~30pt transparent panel inset since hasShadow=false). `if #available(macOS 26)`: prefer **`NSGlassEffectView`** (native `cornerRadius` + `contentView`, replaces the mask dance) or SwiftUI `.glassEffect(...)` where it composes. Respect reduce-transparency → solid fill.

## Integrations (verified on this machine)

### Shared foundation (build first)

- **`ProcessRunner`** (actor): one-shot + streaming (`AsyncThrowingStream` of stdout lines). Drain stdout/stderr concurrently (pipe deadlock). **PATH gotcha:** GUI apps don't get Homebrew PATH — resolve absolute tool paths once via login shell (`/bin/zsh -lic 'echo $PATH'` + `which`), never invoke bare `claude`. Also: kill child processes on cancel (process group), cap captured stderr, and surface non-zero exits as typed errors.
- **`ToolAvailability`** (actor): probe claude/codex/gh/git → `.ok/.missing/.unauthenticated`; gates CTAs with "install X / login" states. Cache probe results; re-probe on demand and on version change (`claude -v` / `codex -V` string stored — feeds schema-drift telemetry below).
- **`FileWatcher`**: FSEvents wrapper → debounced `AsyncStream<Set<URL>>` of changed paths. FSEvents tells *that* something changed; cheap stat/tail tells *what*.

### Coding widget

- Worktrees: `git worktree list --porcelain` → `[Worktree{path, branch, head, prunable}]`.
- **Claude discovery:** slug = worktree path with every `/` AND `.` → `-` (verified: `/.` becomes `--`); scan `~/.claude/projects/<slug>/*.jsonl`. Title from the `ai-title` record. Render `user`/`assistant` records; assistant content = array of `{thinking|text|tool_use|tool_result}`; order by timestamp, skip `isSidechain: true`.
- **Codex discovery:** `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`; line 1 = `session_meta` with `payload.cwd` — filter by cwd == worktree path. Fast-list via `~/.codex/session_index.jsonl` (verified: `{id, thread_name, updated_at}`, no cwd — confirm from rollout line 1, cache id→cwd).
- Normalize both into `TranscriptMessage{role, blocks, timestamp}` via `TranscriptParser` protocol (Claude + Codex impls) with **incremental tail-parse** (byte offset, partial-line buffer — never re-parse whole file).
- **Schema-drift defense (both parsers):** these JSONL formats are unversioned and change across CLI releases. Rules: decode tolerantly (unknown record `type`s → preserved `.unknown(raw:)` block, never a throw; missing optional fields never fail a message); one malformed line skips that line, not the file; count skipped/unknown records per session and surface "N unrecognized entries — transcript may be incomplete" in the chat UI plus `Logger` output keyed by the recorded CLI version. Fixtures are sanitized copies of real session files checked into `Tests/Fixtures/` with a `Scripts/refresh-fixtures.sh` to re-capture after CLI upgrades; contract tests assert both "parses current fixtures fully" and "gracefully degrades on mutated/unknown-type fixtures".
- **Liveness** (`historical | liveIdle | liveBusy | unknown`): primary = JSONL appended within ~30–60s; Codex authoritative via `~/.codex/process_manager/chat_processes.json` (verified present); Claude confirm via process scan + cwd. No lock files exist — heuristic only; the UI copy must hedge ("recently active"), and send-message uses the fork guard below regardless. Live avatar = pulsing ring.
- **Continue conversation (MVP):** headless per-message
  `claude --resume <id> -p "<msg>" --output-format stream-json --verbose` (**`--verbose` is mandatory** with `-p` + stream-json — verified error otherwise). Optional `--include-partial-messages` for token-level streaming into the bubble; parse `stream-json` events tolerantly (same drift rules as transcripts: dispatch on `type`, ignore unknown event types, extract text/tool_use blocks defensively). Set `--max-budget-usd` as a safety cap.
  - **Permission policy (headless mode never prompts — silent denial by default):** MVP runs with `--permission-mode dontAsk` plus an `--allowedTools` read-only whitelist (`Read`, `Grep`, `Glob`, `Bash(git status*)`-style patterns). Tool denials appear in the stream — render them in the chat as "Claude wanted to run X — denied (headless)" instead of losing them. Per-widget setting can raise to `acceptEdits`; `bypassPermissions` is never a default. (Note: `--permission-prompt-tool` no longer exists in current CLI; do not design around it. A later power-mode can use `--input-format stream-json` + the SDK control protocol for interactive approvals, but that is explicitly out of MVP scope.)
  - **Never in-place-resume a session owned by another live process** (JSONL corruption) — offer `--fork-session` (verified) or read-only tail. Forking creates a *new* session id: the chat window must re-bind to the forked id (read result `session_id` from the stream) and the chat-head list will show the fork as a new session — treat as expected UX, label "forked from …".
  - Codex later: `codex exec resume <id> "<msg>" --json` (verified; JSONL events on stdout, `-o` for final message). Embedded terminal (SwiftTerm) = later power-mode; Agent SDK sidecar = only if CLI proves limiting.
- `SpawnSessionService.startClaude(in: worktree, prompt:)` — new sessions; pass a pre-generated UUID via `--session-id <uuid>` (verified flag) so the widget knows the session file to watch immediately instead of racing discovery; shared with meeting widget; new sessions appear as chat-heads automatically (discovery is file-driven).
- One `AgentSessionDriver` protocol (loadTranscript / follow / sendMessage) so chat window is tool-agnostic.

### Reviewer widget

- Flow: parse URL → `gh pr view --json headRefOid,title,author,baseRefName,state,isDraft,mergedAt,reviewDecision,changedFiles` (all fields verified) + `gh pr diff` → `claude -p` **with `--output-format json --json-schema '<findings schema>'`** (verified flag) so findings are schema-validated by the CLI itself; keep one fenced-block-extraction + repair retry only as fallback for schema-mode failure.
- Model: `ReviewSubject{owner,repo,prNumber}` parent + `ReviewRun{headSHA, status, findings[], promptVersion, timestamps}` children — history = runs list.
- Staleness: stored headSHA vs `gh pr view --json headRefOid,state,mergedAt`; check on widget focus + every 5 min while visible; never poll closed/merged (use `state`/`mergedAt` to stop).
- Bounded queue (max 2–3 concurrent claude runs), cancellable; re-run cancels in-flight.
- Edge cases: gh missing/unauthed CTAs, non-PR URLs, huge diffs (MVP: cap by `changedFiles`/byte size + warn), fork PRs (`isCrossRepository` — `gh pr diff` handles them via API), draft PRs labeled.

### Meeting widget (Granola — HTTP API, path decided by spike M8a)

- **Local cache is encrypted** (verified): `cache-v6.json.enc`, `granola.db` (encrypted blob), `storage.dek` wrapped by Keychain item "Granola Safe Storage". Do NOT build on plaintext cache.
- **Three candidate sources, ranked (spike M8a picks one):**
  - **A1 — Official Granola API** (now exists, docs.granola.ai): `grn_` API key auth, list-notes (with `created_after` + cursor pagination) and note-with-transcript endpoints, rate limit 5 req/s sustained. **Caveat:** API-key creation is Business-plan-and-above; only notes with generated summary+transcript appear. If Jen's plan allows a key, this is the winner — stable, documented, no token theft.
  - **A2 — Reverse-engineered app API:** `POST https://api.granola.ai/v2/get-documents`, `POST https://api.granola.ai/v1/get-document-transcript`, Bearer = WorkOS `access_token` extracted from Granola's local state (Keychain-decrypt `storage.dek` → decrypt local storage), refreshed via WorkOS `/user_management/authenticate` with **refresh-token rotation** (a stolen-then-rotated token can break the Granola app itself — spike must confirm read-only token reuse doesn't rotate, or only refresh when Granola is closed). Undocumented and fragile.
  - **C — Local decrypt of `cache-v6.json.enc`:** last resort; documented but most brittle across Granola updates.
- Widget code depends only on a `MeetingSource` protocol (`recentMeetings(since:)`, `transcript(id:)`) so A1/A2 swap freely after the spike.
- Poll 30–60s for completed docs (end time + transcript ready, id not in `ProcessedMeetings` dedupe table) — comfortably inside official rate limits; on auth failure CTA "open Granola / sign in" (A2) or "check API key" (A1).
- Extract via `claude -p --output-format json --json-schema '<action items schema>'` → `[ActionItem{text, owner?, isImmediate, suggestedPrompt}]`.
- Immediate items → edge toast (non-activating panel, auto-hide ~12s, hover-to-persist, stack): Copy prompt (NSPasteboard) / Run with Claude → worktree picker → `SpawnSessionService`.
- Privacy: transcripts local-only, never logged, purgeable; API keys/tokens in Keychain, never in widgets.json.

### Future widget ideas (documented, not built)

Agent Fleet Monitor (all live sessions across repos), Next-Meeting HUD, Prompt Library, CI/PR status strip ("have Claude investigate failure"), Inbox Triage, Worktree Launcher.

## Milestones

Order is strict M0→M7 (each builds on the previous); **M8a is dependency-free after M0 and should be run early in parallel** (it's a command-line spike, not app code) so its outcome can't stall M8b.

- **M0 — floats**: project.yml, Makefile, packages skeleton, LSUIElement + MenuBarExtra, FloatingPanel + one hard-coded glass panel, drag, ⌥Space toggle, hidden Edit menu + `performKeyEquivalent` handler, hit-test pass-through for the transparent shadow inset.
  *Exit:* `make build` green; panel floats over fullscreen Safari; with **Finder frontmost** a text field in the panel accepts typing AND ⌘C/⌘V/⌘A work without the app activating (Finder stays active); clicks in the transparent 30pt margin reach the window behind; position restores across relaunch.
- **M1 — plugin system**: WidgetDescriptor/Registry/Store, PanelManager reconciliation, gallery "+" flow, multi-instance, remove, JSON round-trip + unknown-type placeholder.
  *Exit:* add 3 dummy widgets (one multi-instance ×2), relaunch → all restore with positions; hand-edit widgets.json to an unknown typeID → placeholder renders and the record survives the next save; corrupt the file → `.bak` created, app launches clean.
- **M2 — placement polish**: screen-UUID placement, SnapEngine, screen-change clamp, cascade for new widgets.
  *Exit:* SnapEngine + PanelPlacement unit tests green; drag widget to 2nd display, relaunch → same display; change display resolution / disconnect display → panel clamps into a visible frame (manual smoke); two new widgets cascade instead of stacking.
- **M3 — aux windows**: presentAuxiliaryWindow, child-window anchoring, chat-heads demo widget.
  *Exit:* demo chat-head opens an anchored aux panel; dragging the parent moves the child; invoking the same key twice focuses instead of duplicating; closing parent closes child; parent+child follow across Spaces (or the manual-follow fallback is implemented and a note recorded).
- **M4 — glass & motion**: full glass stack with `maskImage` corner rounding, `NSGlassEffectView`/`.glassEffect` branch behind `#available(macOS 26)`, reduce-transparency fallback, hover chrome, show/hide animation.
  *Exit:* behind-window blur visibly samples a fullscreen app underneath with clean 24pt rounded corners (no square blur halo); Reduce Transparency in System Settings → solid fill immediately; ⌥Space hide/show animates; both macOS-26 and fallback code paths compile and are runtime-selected correctly.
- **M5 — foundation services**: ProcessRunner (+login-shell PATH resolution, process-group kill), ToolAvailability (+version capture), FileWatcher, Settings (hotkey recorder via KeyboardShortcuts, launch-at-login via SMAppService). *(GRDB moved to M7 — first real consumer.)*
  *Exit:* unit tests: ProcessRunner streams a fixture script's stdout lines and kills a hung child on cancel; FileWatcher fires within debounce window on file append; from an app bundle launched via **Finder** (not Xcode), ToolAvailability resolves absolute paths for claude/codex/gh and a live `claude -p "say hi" --output-format stream-json --verbose` round-trips; hotkey re-record works; launch-at-login toggles.
- **M6 — Coding widget MVP**: worktree scan, Claude+Codex discovery, transcript render (read-only + live tail), schema-drift-tolerant parsers + fixture contract tests, liveness heuristic, avatars, continue-via-headless-claude with permission policy, fork-if-live with session re-bind.
  *Exit:* widget lists this repo's real worktrees and real Claude+Codex sessions; opening a transcript renders text/thinking/tool blocks; while a real `claude` session runs in a terminal, new messages appear in the widget within ~2s (tail, not re-parse — verified by log counters); sending a message to an idle session streams the reply and the on-disk JSONL gains the turn; sending to a live-busy session offers fork, and the fork appears as a new labeled chat-head; a denied tool call renders as a visible denial row; mutated-fixture contract tests green.
- **M7 — Reviewer widget MVP**: GRDB store introduced here; URL → review → findings by severity → history; re-run + staleness.
  *Exit:* pasting a real PR URL yields schema-valid findings grouped by severity; run rows persist across relaunch (GRDB); pushing a new commit to the PR → widget flags stale on focus and re-run replaces in-flight; merged/closed PRs stop polling; gh unauthenticated shows login CTA; JSON-schema fallback repair path covered by a unit test.
- **M8a — Granola API spike (de-risk, parallelizable after M0):** standalone `Scripts/granola-spike` (Swift script or small SPM executable, no app dependencies). Tasks: (1) check whether Jen's plan can mint an official `grn_` API key; (2) if yes, prove list-notes + transcript fetch against real data; (3) if no, prove A2: locate + decrypt the WorkOS token from Granola's encrypted local state, call `v2/get-documents` + `v1/get-document-transcript`, and characterize refresh-rotation risk; (4) write findings + the chosen path to `docs/integrations/granola.md`.
  *Exit:* spike script prints the 5 most recent meetings and one full transcript via ONE proven auth path; decision (A1/A2/C) recorded with endpoint request/response samples; go/no-go for M8b (if all paths fail, Meeting widget is re-scoped to manual paste-transcript and that decision is recorded).
- **M8b — Meeting widget MVP**: `MeetingSource` impl per the spike decision, poll + dedupe, action-item extraction (`--json-schema`), edge toasts, Run-with-Claude spawn via `--session-id`.
  *Exit:* after a real (or replayed-fixture) meeting completes, a toast appears within one poll interval; toast auto-hides ~12s and persists on hover; Copy prompt fills the pasteboard; Run with Claude → worktree picker → new session spawns and its chat-head appears in the coding widget; same meeting never triggers twice across relaunches; auth failure shows the correct CTA.

## Verification

- `make gen && make build` (xcodebuild) green at every milestone; `make test` = xcodebuild test + `swift test` in JoshuKit.
- Unit tests: store round-trip/corruption/unknown-type, SnapEngine math, PanelPlacement fraction↔frame + clamping, transcript parsers against fixture JSONL copied from real `~/.claude`/`~/.codex` sessions (sanitized, refreshed via `Scripts/refresh-fixtures.sh`), **drift tests against mutated fixtures (unknown record types, missing fields, truncated lines)**, slug builder, stream-json event parsing incl. tool-denial events, review JSON-schema fallback repair, ProcessRunner cancel/kill.
- Manual smoke checklist (`docs/SMOKE.md`): menu-bar-only launch, gallery add, drag to 2nd monitor, hotkey hide/show, **type + ⌘C/⌘V while Finder frontmost (app must not activate)**, click-through on transparent shadow inset, overlay over fullscreen app, relaunch restore, display-unplug clamp, Reduce Transparency fallback. (XCUITest useless for nonactivating borderless panels.)
- Integration smoke: coding widget against this machine's real sessions (incl. one deliberately running live in a terminal); reviewer against a real PR URL; Granola spike script re-run before M8b starts (guards against Granola app updates between milestones); `log stream --predicate 'subsystem == "com.wren.joshu"'` for CLI-visible logging, including parser-drift counters and permission-denial events.
- After any `claude`/`codex` CLI upgrade during development: re-run fixture refresh + contract tests before continuing (drift is a when, not an if).

## Notes for implementation

- Per superpowers flow: on approval, first write this design as spec to `docs/superpowers/specs/2026-07-02-joshu-overlay-widgets-design.md`, commit, then implement milestone-by-milestone with TDD where testable (parsers, store, snap math, ProcessRunner).
- Dependencies: KeyboardShortcuts (SPM, macOS 10.15+ — fine), GRDB 7.x (SPM, from M7; needs Xcode 16.3+/Swift 6.1 — satisfied by Xcode 26.6). Nothing else.
- Headless `claude` invocations: always `-p --verbose` with stream-json; always an explicit `--permission-mode`; always `--max-budget-usd`; never bare `claude` (absolute path from ToolAvailability).
