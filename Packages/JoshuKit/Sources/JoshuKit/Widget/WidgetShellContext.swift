import SwiftUI

/// How an auxiliary window relates to its widget's main panel.
public struct AuxiliaryWindowOptions: Sendable {
    public enum AnchorEdge: Sendable {
        case leading, trailing, top, bottom
    }

    public enum Attachment: Sendable {
        /// Independent floating window.
        case detached
        /// Rides along with the parent panel (child window), offset from the
        /// given glass edge by `gap`.
        case anchored(edge: AnchorEdge, gap: CGFloat)
    }

    /// Size of the visible glass (the shell adds the shadow inset).
    public var size: CGSize
    public var attachment: Attachment

    public init(size: CGSize, attachment: Attachment = .detached) {
        self.size = size
        self.attachment = attachment
    }
}

public struct AuxiliaryWindowHandle {
    public let key: String
    public let close: @MainActor () -> Void

    public init(key: String, close: @escaping @MainActor () -> Void) {
        self.key = key
        self.close = close
    }
}

/// The widget's only doorway to the shell that hosts it. Widgets never touch
/// AppKit; on macOS the shell is an NSPanel layer, on visionOS auxiliary
/// windows map to `openWindow` scenes.
@MainActor
public protocol WidgetShellContext: AnyObject {
    /// Persist a config mutation for this instance.
    func configDidChange(_ instanceID: UUID, _ configJSON: Data)

    /// Remove this widget instance entirely (close panel, drop record).
    func removeSelf(_ instanceID: UUID)

    /// Present (or focus, if `key` already exists) a floating auxiliary
    /// window owned by this widget — e.g. a chat window off a chat-head.
    /// Not persisted: widgets recreate aux windows from their own config.
    @discardableResult
    func presentAuxiliaryWindow(
        key: String,
        options: AuxiliaryWindowOptions,
        content: @escaping () -> AnyView
    ) -> AuxiliaryWindowHandle

    func dismissAuxiliaryWindow(key: String)
}

extension WidgetShellContext {
    /// Type-inferring sugar so widgets don't spell AnyView.
    @discardableResult
    public func presentAuxiliaryWindow<Content: View>(
        key: String,
        options: AuxiliaryWindowOptions,
        @ViewBuilder content: @escaping () -> Content
    ) -> AuxiliaryWindowHandle {
        presentAuxiliaryWindow(key: key, options: options) { AnyView(content()) }
    }
}
