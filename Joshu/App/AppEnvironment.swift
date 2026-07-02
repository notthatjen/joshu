import AppKit
import Observation

/// Composition root. Owns the panel layer and global services.
/// M0: a single hard-coded demo panel. M1 replaces this with
/// WidgetStore + WidgetRegistry + PanelManager reconciliation.
@MainActor
@Observable
final class AppEnvironment {
    private(set) var panelsVisible = true

    @ObservationIgnored private var demoPanel: PanelController?
    @ObservationIgnored private var hotkey: HotkeyManager?

    func start() {
        let controller = PanelController()
        controller.show()
        demoPanel = controller

        let hotkey = HotkeyManager()
        hotkey.onToggle = { [weak self] in self?.toggleVisibility() }
        self.hotkey = hotkey
    }

    func toggleVisibility() {
        panelsVisible.toggle()
        if panelsVisible {
            demoPanel?.show()
        } else {
            demoPanel?.hide()
        }
    }
}
