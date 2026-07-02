import AppKit
import SwiftUI
import JoshuKit

/// Owns one FloatingPanel hosting one widget instance. Reports frame changes
/// back to the store and runs the widget's optional background service.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let instanceID: UUID

    private let panel: FloatingPanel
    private let onFrameChanged: (UUID, NSRect) -> Void
    private var service: (any WidgetService)?
    private var serviceTask: Task<Void, Never>?

    init(
        record: WidgetInstanceRecord,
        content: AnyView,
        service: (any WidgetService)?,
        cascadeIndex: Int,
        onFrameChanged: @escaping (UUID, NSRect) -> Void
    ) {
        instanceID = record.id
        self.service = service
        self.onFrameChanged = onFrameChanged

        let frame = Self.initialFrame(for: record.placement, cascadeIndex: cascadeIndex)
        panel = FloatingPanel(contentRect: frame)
        super.init()
        panel.delegate = self

        let container = PassThroughMarginView()
        container.margin = JoshuTheme.shadowInset

        let host = NSHostingView(rootView: WidgetChrome { content })
        // Default sizingOptions let SwiftUI's intrinsic size drive the window
        // frame; the stored placement is the boss.
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

        if record.placement.origin == nil {
            // Freshly cascaded: persist the chosen spot right away.
            onFrameChanged(instanceID, panel.frame)
        }

        if let service {
            serviceTask = Task { await service.start() }
        }
    }

    private static func initialFrame(for placement: PanelPlacement, cascadeIndex: Int) -> NSRect {
        if let origin = placement.origin {
            return NSRect(origin: origin, size: placement.size)
        }
        // Cascade new panels from the screen center so stacked instances
        // don't hide each other.
        let screen = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offset = CGFloat(cascadeIndex % 8) * 28
        let origin = NSPoint(
            x: screen.midX - placement.size.width / 2 + offset,
            y: screen.midY - placement.size.height / 2 - offset
        )
        return NSRect(origin: origin, size: placement.size)
    }

    // MARK: - Visibility & teardown

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    func close() {
        let service = service
        self.service = nil
        serviceTask?.cancel()
        Task { await service?.stop() }
        panel.delegate = nil
        panel.close()
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        onFrameChanged(instanceID, panel.frame)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        onFrameChanged(instanceID, panel.frame)
    }
}
