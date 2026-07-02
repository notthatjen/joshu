import Foundation
import JoshuKit

/// macOS implementation of the widget → shell doorway. Closure-based so it
/// holds no strong reference back into the app environment.
@MainActor
final class MacWidgetShellContext: WidgetShellContext {
    private let onConfigChange: (UUID, Data) -> Void
    private let onRemove: (UUID) -> Void

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
}
