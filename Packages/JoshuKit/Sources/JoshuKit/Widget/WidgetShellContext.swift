import Foundation

/// The widget's only doorway to the shell that hosts it. Widgets never touch
/// AppKit; on macOS the shell is an NSPanel layer, on visionOS it will map to
/// window scenes. Auxiliary-window presentation lands here in M3.
@MainActor
public protocol WidgetShellContext: AnyObject {
    /// Persist a config mutation for this instance.
    func configDidChange(_ instanceID: UUID, _ configJSON: Data)

    /// Remove this widget instance entirely (close panel, drop record).
    func removeSelf(_ instanceID: UUID)
}
