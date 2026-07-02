import AppKit
import SwiftUI
import JoshuKit

/// One auxiliary floating window (chat window, detail popout) owned by a
/// widget instance. Anchored windows become child windows of the parent panel
/// so they ride along when it's dragged.
@MainActor
final class AuxiliaryPanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    private weak var parentPanel: NSPanel?
    var onClosed: (() -> Void)?

    init(options: AuxiliaryWindowOptions, content: AnyView, parentPanel: NSPanel?) {
        let inset = JoshuTheme.shadowInset
        let frameSize = NSSize(
            width: options.size.width + inset * 2,
            height: options.size.height + inset * 2
        )
        let frame = Self.frame(
            size: frameSize, attachment: options.attachment, parentFrame: parentPanel?.frame, inset: inset)

        panel = FloatingPanel(contentRect: frame)
        self.parentPanel = parentPanel
        super.init()
        panel.delegate = self

        let container = PassThroughMarginView()
        container.margin = inset
        let host = NSHostingView(rootView: WidgetChrome(onClose: { [weak self] in self?.close() }) { content })
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
        panel.setFrame(frame, display: false)

        if case .anchored = options.attachment, let parentPanel {
            parentPanel.addChildWindow(panel, ordered: .above)
        }
    }

    private static func frame(
        size: NSSize,
        attachment: AuxiliaryWindowOptions.Attachment,
        parentFrame: NSRect?,
        inset: CGFloat
    ) -> NSRect {
        guard case let .anchored(edge, gap) = attachment, let parentFrame else {
            // Detached: centered on the main screen.
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NSRect(
                x: screen.midX - size.width / 2,
                y: screen.midY - size.height / 2,
                width: size.width, height: size.height
            )
        }

        // Position glass-edge to glass-edge with `gap` between.
        let parentGlass = parentFrame.insetBy(dx: inset, dy: inset)
        var glass = NSRect(origin: .zero, size: NSSize(width: size.width - inset * 2, height: size.height - inset * 2))

        switch edge {
        case .trailing:
            glass.origin = NSPoint(x: parentGlass.maxX + gap, y: parentGlass.maxY - glass.height)
        case .leading:
            glass.origin = NSPoint(x: parentGlass.minX - gap - glass.width, y: parentGlass.maxY - glass.height)
        case .top:
            glass.origin = NSPoint(x: parentGlass.minX, y: parentGlass.maxY + gap)
        case .bottom:
            glass.origin = NSPoint(x: parentGlass.minX, y: parentGlass.minY - gap - glass.height)
        }

        var frame = glass.insetBy(dx: -inset, dy: -inset)
        if let screen = NSScreen.main?.visibleFrame {
            frame = PanelPlacementResolver.clamp(frame, into: screen)
        }
        return frame
    }

    func show() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func bringToFront() {
        show()
    }

    func close() {
        parentPanel?.removeChildWindow(panel)
        panel.delegate = nil
        panel.close()
        onClosed?()
    }
}
