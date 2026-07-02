import AppKit

/// The overlay window every widget lives in: borderless, nonactivating,
/// floats above normal windows and over fullscreen apps.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // glass shadow is drawn in SwiftUI inside the shadow inset
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    // Borderless windows refuse key status by default, which silently breaks
    // all text input. The panel must be able to become key while the app
    // itself stays inactive (that's the .nonactivatingPanel part).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // The app never activates, so main-menu key equivalents never fire for
    // panel-hosted fields. Route the standard edit shortcuts to the first
    // responder ourselves.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command || modifiers == [.command, .shift] else { return false }

        let action: Selector?
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "x": action = modifiers == .command ? #selector(NSText.cut(_:)) : nil
        case "c": action = modifiers == .command ? #selector(NSText.copy(_:)) : nil
        case "v": action = modifiers == .command ? #selector(NSText.paste(_:)) : nil
        case "a": action = modifiers == .command ? #selector(NSText.selectAll(_:)) : nil
        case "z": action = modifiers == .command ? Selector(("undo:")) : Selector(("redo:"))
        default: action = nil
        }

        guard let action else { return false }
        // nil target walks the key window's responder chain (this panel).
        return NSApp.sendAction(action, to: nil, from: self)
    }
}
