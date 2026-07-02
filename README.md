# Joshu

Floating, always-on-top glass assistant widgets for macOS (visionOS/Liquid-Glass
aesthetic). A menu-bar app that overlays interactive widgets hosting AI
assistants over everything else.

## Widgets

- **Coding** — one instance per repo. Scans git worktrees, discovers existing
  Claude Code / Codex sessions per worktree, shows them as stacked chat-head
  avatars (live sessions pulse), and opens floating chat windows to read the
  transcript and continue the conversation (headless `claude --resume`,
  fork-if-live).
- **Reviewer** — paste a GitHub PR URL → AI review (`gh` + headless `claude`
  with a JSON schema) → findings by severity, history, and staleness
  detection with re-run.
- **Meeting** — watches Granola for finished meetings, extracts action items,
  and pops immediate ones as edge toasts with *Copy prompt* / *Run with
  Claude* (spawns a session in a chosen workspace — which then shows up in the
  Coding widget).
- **Notes**, **Chat Heads (demo)** — small built-ins that exercise the config
  and auxiliary-window plumbing.

## Build & run

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
make gen     # generate Joshu.xcodeproj from project.yml
make build   # xcodebuild
make test    # swift test (JoshuKit) + app build
make run     # build + launch
```

The app is a menu-bar item (no Dock icon). ⌥Space toggles all widgets; add
widgets from the menu-bar "Add Widget…" gallery.

## Architecture

- `Joshu/` — the app target, the only code that touches AppKit. `FloatingPanel`
  (nonactivating borderless `NSPanel`), `PanelManager` reconciling the store to
  live panels, glass chrome (`NSVisualEffectView` behind-window blur with
  `maskImage` rounding, or `.glassEffect` on macOS 26), auxiliary/toast windows.
- `Packages/JoshuKit/` — platform-agnostic core (no AppKit): the widget plugin
  protocol, registry, JSON store, placement/snap math, `ProcessRunner`,
  `ToolAvailability`, `FileWatcher`, and the Claude/Codex transcript parsers.
  Kept AppKit-free for a future visionOS port.
- `Packages/JoshuWidgets/` — the built-in widget types, depending only on
  JoshuKit + GRDB (reviewer/meeting history).

New widget types conform to `WidgetDescriptor` (type id + metadata + `Codable`
config + SwiftUI view + optional background service) and are registered in
`BuiltinWidgets.all`.

## Docs

- `docs/superpowers/specs/2026-07-02-joshu-overlay-widgets-design.md` — the
  design spec.
- `docs/integrations/granola.md` — Granola API findings (M8a spike).
- `docs/SMOKE.md` — manual smoke checklist per milestone (XCUITest can't drive
  nonactivating borderless panels).

## Status

Milestones M0–M8b implemented (window shell → plugin system → placement →
auxiliary windows → glass → foundation services → coding → reviewer → Granola
spike → meeting). 58 unit tests. The Meeting widget's live path needs a
one-time Keychain grant to decrypt Granola's credentials (see the integration
doc); everything else runs against real local data.
