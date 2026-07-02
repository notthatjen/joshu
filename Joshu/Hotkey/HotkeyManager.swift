import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleAllWidgets = Self(
        "toggleAllWidgets",
        default: .init(.space, modifiers: [.option])
    )
}

/// Global hotkey registration. KeyboardShortcuts wraps Carbon's
/// RegisterEventHotKey — the only way to consume a global shortcut without
/// Accessibility permission.
@MainActor
final class HotkeyManager {
    var onToggle: (() -> Void)?

    init() {
        KeyboardShortcuts.onKeyUp(for: .toggleAllWidgets) { [weak self] in
            self?.onToggle?()
        }
    }
}
