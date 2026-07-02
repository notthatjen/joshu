import SwiftUI
import JoshuKit

/// macOS implementation of the widget → shell doorway. Owns the widget's
/// auxiliary windows; anchoring needs the main panel, attached by
/// PanelManager right after the PanelController is created.
@MainActor
final class MacWidgetShellContext: WidgetShellContext {
    weak var panelController: PanelController?

    private let onConfigChange: (UUID, Data) -> Void
    private let onRemove: (UUID) -> Void
    private var auxWindows: [String: AuxiliaryPanelController] = [:]

    init(
        onConfigChange: @escaping (UUID, Data) -> Void,
        onRemove: @escaping (UUID) -> Void
    ) {
        self.onConfigChange = onConfigChange
        self.onRemove = onRemove
    }

    func configDidChange(_ instanceID: UUID, _ configJSON: Data) {
        onConfigChange(instanceID, configJSON)
    }

    func removeSelf(_ instanceID: UUID) {
        onRemove(instanceID)
    }

    @discardableResult
    func presentAuxiliaryWindow(
        key: String,
        options: AuxiliaryWindowOptions,
        content: @escaping () -> AnyView
    ) -> AuxiliaryWindowHandle {
        if let existing = auxWindows[key] {
            existing.bringToFront()
        } else {
            let aux = AuxiliaryPanelController(
                options: options,
                content: content(),
                parentPanel: panelController?.nsPanel
            )
            aux.onClosed = { [weak self] in self?.auxWindows[key] = nil }
            auxWindows[key] = aux
            aux.show()
        }
        return AuxiliaryWindowHandle(key: key) { [weak self] in
            self?.dismissAuxiliaryWindow(key: key)
        }
    }

    func dismissAuxiliaryWindow(key: String) {
        auxWindows[key]?.close()
    }

    /// Widget instance removed or app quitting: tear down every aux window.
    func closeAllAuxiliaryWindows() {
        for aux in auxWindows.values {
            aux.close()
        }
        auxWindows.removeAll()
    }
}
