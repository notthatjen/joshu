import Foundation
import Observation

/// Per-instance live object handed to the widget's view. Mutating `config`
/// flows straight into the store via the shell context.
@MainActor
@Observable
public final class WidgetModel<Config: WidgetConfig> {
    public let instanceID: UUID
    public let shell: any WidgetShellContext

    public var config: Config {
        didSet {
            guard config != oldValue, let data = try? JSONEncoder().encode(config) else { return }
            shell.configDidChange(instanceID, data)
        }
    }

    public init(instanceID: UUID, config: Config, shell: any WidgetShellContext) {
        self.instanceID = instanceID
        self.config = config
        self.shell = shell
    }

    public func removeSelf() {
        shell.removeSelf(instanceID)
    }
}
