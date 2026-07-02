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
