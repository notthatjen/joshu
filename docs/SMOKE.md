# Manual smoke checklist

XCUITest can't drive nonactivating borderless panels, so these are verified by
hand after each milestone. Run `make run` first.

## M0 — window shell

- [ ] Menu bar shows the ✨ Joshu item; no Dock icon appears.
- [ ] Glass panel floats above other windows, including a fullscreen app.
- [ ] Panel drags from anywhere on the glass surface.
- [ ] With **Finder frontmost**: click the text field and type — text appears
      and Finder stays the active app (its menu bar remains).
- [ ] ⌘C/⌘V/⌘A/⌘X work in the text field while the app is inactive.
- [ ] Clicks in the transparent shadow margin (~30pt around the glass) land on
      the window beneath the panel.
- [ ] ⌥Space hides all widgets; ⌥Space again shows them.
- [ ] Menu bar → Hide Widgets / Show Widgets mirrors the hotkey.
- [ ] Drag the panel somewhere, quit (menu bar → Quit Joshu), `make run`
      again — panel restores to the same position.
- [ ] Two displays: drag panel to the second display, relaunch — it comes back
      on that display.

## M2 — placement

- [ ] Drag a widget near a screen edge and release — it snaps flush.
- [ ] Drag one widget next to another — edges snap together.
- [ ] Change display resolution (or unplug a display) — widgets jump back
      into the visible area.

## M3 — auxiliary windows (Chat Heads demo)

- [ ] Add "Chat Heads (demo)" from the gallery.
- [ ] Click an avatar — a chat window opens anchored to the right of the stack.
- [ ] Drag the avatar stack — the chat window rides along.
- [ ] Click the same avatar again — the existing window focuses (no duplicate).
- [ ] Type in the chat text field and press ⏎ — message appears.
- [ ] Remove the widget (menu bar → Remove Widget) — its chat windows close too.
- [ ] Switch Spaces with a chat window open — parent and child stay together.

## M6 — coding widget

- [ ] Add "Coding" from the gallery; paste a repo path — worktrees appear.
- [ ] Sessions show as avatars per worktree (C = Claude, X = Codex); a
      session that wrote to disk in the last ~45s pulses green.
- [ ] Click an avatar — chat window opens with the transcript (text bubbles,
      collapsed "thinking", compact tool rows).
- [ ] While a claude session runs in a terminal in that worktree, new
      messages appear in the open chat window within ~2s.
- [ ] Send a message to an idle Claude session — reply streams in and the
      on-disk JSONL gains the turn (headless: read-only tools allowed,
      denials render as rows).
- [ ] Send to a session that's active elsewhere — it forks ("forked from …"
      banner) and the fork appears as a new avatar.
- [ ] Codex sessions open read-only with live tail.

## M7 — reviewer widget

- [ ] Add "Reviewer" from the gallery — empty state shows just the URL input.
- [ ] Paste a real PR URL — row appears as "running", then "completed" with
      findings grouped by severity (each full review costs real Claude usage).
- [ ] Click a row — detail window opens with summary + findings.
- [ ] Push a new commit to that PR, wait ≤5 min (or relaunch) — row flips to
      "stale" with a Re-run button; re-running adds a new run to history.
- [ ] Merged/closed PRs stop being polled.
- [ ] `gh auth logout` state shows a login CTA instead of failing silently.

## M8b — meeting widget

Needs a one-time interactive step (see docs/integrations/granola.md):
- [ ] Add "Meeting" from the gallery — background poll uses only the no-prompt
      plaintext token; when that's stale it shows "Connect" (no surprise
      Keychain prompt).
- [ ] Click Connect (with the user present) — approve the one-time
      "Granola Safe Storage" Keychain prompt; meetings begin loading.
- [ ] After a real meeting completes in Granola, within one poll (~45s) its
      immediate action items pop as top-right edge toasts.
- [ ] Toast auto-hides ~12s; hovering keeps it up.
- [ ] "Copy prompt" fills the pasteboard with the suggested prompt.
- [ ] "Run with Claude" spawns a session in the default workspace and its
      chat-head appears in the coding widget for that repo.
- [ ] Relaunch — the same meeting is not processed again (dedupe).
