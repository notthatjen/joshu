import AppKit
import SwiftUI
import JoshuKit

/// Owns one FloatingPanel. M0: hosts the hard-coded demo widget and restores
/// its frame via autosave. M1 generalizes this to one controller per
/// WidgetInstanceRecord driven by PanelManager.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel

    override init() {
        let inset = JoshuTheme.shadowInset
        let contentSize = NSSize(width: 360 + inset * 2, height: 260 + inset * 2)
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: contentSize))
        super.init()
        panel.delegate = self

        let container = PassThroughMarginView()
        container.margin = inset

        let host = NSHostingView(rootView: DemoWidgetView())
        // Default sizingOptions let SwiftUI's intrinsic size drive the window
        // frame (a Spacer makes that unbounded). The panel frame is the boss.
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

        panel.center()
        // Restores any previously saved frame and persists moves from now on.
        panel.setFrameAutosaveName("joshu.demo-panel")
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }
}
